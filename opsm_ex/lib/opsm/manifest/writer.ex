# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Manifest.Writer do
  @moduledoc """
  Bidirectional manifest conversion — write OPSM's internal ManifestFormat
  to various ecosystem-specific formats.
  """

  alias Opsm.Types.ManifestFormat

  @doc """
  Convert a ManifestFormat to a target format string.

  Supported targets: `:package_json`, `:cargo_toml`, `:mix_exs`,
  `:pyproject_toml`, `:pubspec_yaml`, `:go_mod`, `:opsm_toml`.
  """
  @spec convert(ManifestFormat.t(), atom()) :: {:ok, String.t()} | {:error, String.t()}
  def convert(%ManifestFormat{} = manifest, target) do
    case target do
      :package_json -> {:ok, to_package_json(manifest)}
      :cargo_toml -> {:ok, to_cargo_toml(manifest)}
      :mix_exs -> {:ok, to_mix_exs(manifest)}
      :pyproject_toml -> {:ok, to_pyproject_toml(manifest)}
      :pubspec_yaml -> {:ok, to_pubspec_yaml(manifest)}
      :go_mod -> {:ok, to_go_mod(manifest)}
      :opsm_toml -> {:ok, to_opsm_toml(manifest)}
      _ -> {:error, "Unsupported target format: #{target}"}
    end
  end

  @doc """
  Generate npm package.json from ManifestFormat.
  """
  @spec to_package_json(ManifestFormat.t()) :: String.t()
  def to_package_json(%ManifestFormat{} = m) do
    json = %{
      "name" => m.name,
      "version" => m.version || "0.0.0",
      "description" => m.description,
      "license" => m.license,
      "homepage" => m.homepage,
      "repository" => m.repository,
      "keywords" => m.keywords || [],
      "dependencies" => format_npm_deps(m.dependencies),
      "devDependencies" => format_npm_deps(m.dev_dependencies)
    }
    |> reject_nil_values()

    json =
      if m.authors != [] do
        Map.put(json, "author", List.first(m.authors))
      else
        json
      end

    json =
      if m.bin != %{} and m.bin != nil do
        Map.put(json, "bin", m.bin)
      else
        json
      end

    Jason.encode!(json, pretty: true)
  end

  @doc """
  Generate Rust Cargo.toml from ManifestFormat.
  """
  @spec to_cargo_toml(ManifestFormat.t()) :: String.t()
  def to_cargo_toml(%ManifestFormat{} = m) do
    lines = [
      "[package]",
      ~s(name = "#{m.name}"),
      ~s(version = "#{m.version || "0.0.0"}"),
      ~s(edition = "2021")
    ]

    lines = if m.description, do: lines ++ [~s(description = "#{escape_toml(m.description)}")], else: lines
    lines = if m.license, do: lines ++ [~s(license = "#{m.license}")], else: lines
    lines = if m.repository, do: lines ++ [~s(repository = "#{m.repository}")], else: lines

    lines =
      if m.authors != [] do
        authors_str = m.authors |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")
        lines ++ ["authors = [#{authors_str}]"]
      else
        lines
      end

    lines =
      if m.keywords != [] do
        kw_str = m.keywords |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")
        lines ++ ["keywords = [#{kw_str}]"]
      else
        lines
      end

    lines = lines ++ [""]

    lines =
      if m.dependencies != %{} and m.dependencies != nil do
        dep_lines =
          Enum.map(m.dependencies, fn {name, version} ->
            ~s(#{name} = "#{normalize_version(version)}")
          end)

        lines ++ ["[dependencies]"] ++ dep_lines ++ [""]
      else
        lines
      end

    lines =
      if m.dev_dependencies != %{} and m.dev_dependencies != nil do
        dep_lines =
          Enum.map(m.dev_dependencies, fn {name, version} ->
            ~s(#{name} = "#{normalize_version(version)}")
          end)

        lines ++ ["[dev-dependencies]"] ++ dep_lines ++ [""]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  @doc """
  Generate Elixir mix.exs from ManifestFormat.
  """
  @spec to_mix_exs(ManifestFormat.t()) :: String.t()
  def to_mix_exs(%ManifestFormat{} = m) do
    app_name = m.name |> String.replace("-", "_") |> String.downcase()
    module_name = app_name |> Macro.camelize()

    deps =
      Enum.map(m.dependencies || %{}, fn {name, version} ->
        dep_name = String.replace(name, "-", "_")
        "      {:#{dep_name}, \"~> #{normalize_version(version)}\"}"
      end)
      |> Enum.join(",\n")

    """
    # SPDX-License-Identifier: #{m.license || "MPL-2.0"}
    defmodule #{module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "#{m.version || "0.0.0"}",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          deps: deps(),
          description: "#{escape_elixir(m.description || "")}",
          package: package()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
    #{deps}
        ]
      end

      defp package do
        [
          licenses: ["#{m.license || "MPL-2.0"}"],
          links: %{}
        ]
      end
    end
    """
  end

  @doc """
  Generate Python pyproject.toml from ManifestFormat.
  """
  @spec to_pyproject_toml(ManifestFormat.t()) :: String.t()
  def to_pyproject_toml(%ManifestFormat{} = m) do
    lines = [
      "[build-system]",
      ~s(requires = ["setuptools>=61.0"]),
      ~s(build-backend = "setuptools.backends"),
      "",
      "[project]",
      ~s(name = "#{m.name}"),
      ~s(version = "#{m.version || "0.0.0"}")
    ]

    lines = if m.description, do: lines ++ [~s(description = "#{escape_toml(m.description)}")], else: lines
    lines = if m.license, do: lines ++ [~s(license = "#{m.license}")], else: lines

    lines =
      if m.authors != [] do
        authors_str =
          m.authors
          |> Enum.map(fn a -> ~s({name = "#{a}"}) end)
          |> Enum.join(", ")

        lines ++ ["authors = [#{authors_str}]"]
      else
        lines
      end

    lines =
      if m.keywords != [] do
        kw_str = m.keywords |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")
        lines ++ ["keywords = [#{kw_str}]"]
      else
        lines
      end

    lines =
      if m.dependencies != %{} and m.dependencies != nil do
        dep_list =
          Enum.map(m.dependencies, fn {name, version} ->
            ~s("#{name}#{format_pypi_version(version)}")
          end)
          |> Enum.join(", ")

        lines ++ ["dependencies = [#{dep_list}]"]
      else
        lines
      end

    lines ++ [""] |> Enum.join("\n")
  end

  @doc """
  Generate Dart pubspec.yaml from ManifestFormat.
  """
  @spec to_pubspec_yaml(ManifestFormat.t()) :: String.t()
  def to_pubspec_yaml(%ManifestFormat{} = m) do
    lines = [
      "name: #{m.name}",
      "version: #{m.version || "0.0.0"}"
    ]

    lines = if m.description, do: lines ++ ["description: \"#{escape_yaml(m.description)}\""], else: lines
    lines = if m.homepage, do: lines ++ ["homepage: #{m.homepage}"], else: lines
    lines = if m.repository, do: lines ++ ["repository: #{m.repository}"], else: lines

    lines = lines ++ ["", "environment:", "  sdk: '>=3.0.0 <4.0.0'"]

    lines =
      if m.dependencies != %{} and m.dependencies != nil do
        dep_lines =
          Enum.map(m.dependencies, fn {name, version} ->
            "  #{name}: ^#{normalize_version(version)}"
          end)

        lines ++ ["", "dependencies:"] ++ dep_lines
      else
        lines
      end

    lines =
      if m.dev_dependencies != %{} and m.dev_dependencies != nil do
        dep_lines =
          Enum.map(m.dev_dependencies, fn {name, version} ->
            "  #{name}: ^#{normalize_version(version)}"
          end)

        lines ++ ["", "dev_dependencies:"] ++ dep_lines
      else
        lines
      end

    Enum.join(lines, "\n") <> "\n"
  end

  @doc """
  Generate Go go.mod from ManifestFormat.
  """
  @spec to_go_mod(ManifestFormat.t()) :: String.t()
  def to_go_mod(%ManifestFormat{} = m) do
    module_path = m.repository || "github.com/unknown/#{m.name}"
    # Strip protocol prefix for Go module path
    module_path =
      module_path
      |> String.replace(~r{^https?://}, "")
      |> String.replace(~r{\.git$}, "")

    lines = [
      "module #{module_path}",
      "",
      "go 1.21",
      ""
    ]

    lines =
      if m.dependencies != %{} and m.dependencies != nil do
        req_lines =
          Enum.map(m.dependencies, fn {name, version} ->
            "\t#{name} v#{normalize_version(version)}"
          end)

        lines ++ ["require ("] ++ req_lines ++ [")", ""]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  @doc """
  Generate OPSM native opsm.toml from ManifestFormat.
  """
  @spec to_opsm_toml(ManifestFormat.t()) :: String.t()
  def to_opsm_toml(%ManifestFormat{} = m) do
    lines = [
      "[package]",
      ~s(name = "#{m.name}"),
      ~s(version = "#{m.version || "0.0.0"}")
    ]

    lines = if m.description, do: lines ++ [~s(description = "#{escape_toml(m.description)}")], else: lines
    lines = if m.license, do: lines ++ [~s(license = "#{m.license}")], else: lines
    lines = if m.homepage, do: lines ++ [~s(homepage = "#{m.homepage}")], else: lines
    lines = if m.repository, do: lines ++ [~s(repository = "#{m.repository}")], else: lines

    lines =
      if m.authors != [] do
        authors_str = m.authors |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")
        lines ++ ["authors = [#{authors_str}]"]
      else
        lines
      end

    lines =
      if m.keywords != [] do
        kw_str = m.keywords |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")
        lines ++ ["keywords = [#{kw_str}]"]
      else
        lines
      end

    lines =
      if m.source_forth do
        lines ++ [~s(source_forth = "#{m.source_forth}")]
      else
        lines
      end

    lines = lines ++ [""]

    lines =
      if m.dependencies != %{} and m.dependencies != nil do
        dep_lines =
          Enum.map(m.dependencies, fn {name, version} ->
            ~s(#{name} = "#{normalize_version(version)}")
          end)

        lines ++ ["[dependencies]"] ++ dep_lines ++ [""]
      else
        lines
      end

    lines =
      if m.dev_dependencies != %{} and m.dev_dependencies != nil do
        dep_lines =
          Enum.map(m.dev_dependencies, fn {name, version} ->
            ~s(#{name} = "#{normalize_version(version)}")
          end)

        lines ++ ["[dev-dependencies]"] ++ dep_lines ++ [""]
      else
        lines
      end

    lines =
      if m.bin != %{} and m.bin != nil do
        bin_lines =
          Enum.map(m.bin, fn {name, path} ->
            ~s(#{name} = "#{path}")
          end)

        lines ++ ["[bin]"] ++ bin_lines ++ [""]
      else
        lines
      end

    Enum.join(lines, "\n")
  end

  # Helpers

  defp reject_nil_values(map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp format_npm_deps(nil), do: %{}
  defp format_npm_deps(deps) when is_map(deps) do
    Enum.map(deps, fn
      {name, version} when is_binary(version) ->
        # Ensure npm-style version prefix
        {name, if(String.starts_with?(version, "^") or String.starts_with?(version, "~") or String.starts_with?(version, ">"), do: version, else: "^#{version}")}
      {name, version} ->
        {name, "^#{version}"}
    end)
    |> Map.new()
  end

  defp normalize_version(version) when is_binary(version) do
    version
    |> String.trim_leading("^")
    |> String.trim_leading("~")
    |> String.trim_leading(">=")
    |> String.trim_leading(">")
    |> String.trim_leading("=")
    |> String.trim()
  end

  defp normalize_version(version), do: to_string(version)

  defp format_pypi_version(version) when is_binary(version) do
    cleaned = normalize_version(version)
    if cleaned == "" or cleaned == "*", do: "", else: ">=#{cleaned}"
  end

  defp format_pypi_version(_), do: ""

  defp escape_toml(str), do: String.replace(str, "\"", "\\\"")
  defp escape_elixir(str), do: String.replace(str, "\"", "\\\"")
  defp escape_yaml(str), do: String.replace(str, "\"", "\\\"")
end
