# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Hackage do
  @moduledoc """
  Hackage (Haskell) Registry API client.
  https://hackage.haskell.org/api
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://hackage.haskell.org"

  # GHC built-in, wired-in, and flag-guard packages that don't exist on Hackage
  @ghc_builtins ~w(
    base rts ghc-prim ghc-bignum integer-gmp integer-simple
    template-haskell ghc-boot ghc-boot-th ghc-heap ghc-compact
    unbuildable system-cxx-std-lib invalid-cabal-flag-settings
    ghc ghc-lib ghc-lib-parser
    hostname Win32 unix
  )

  @doc """
  Fetch package metadata from Hackage.
  """
  def fetch_package(name, version \\ "latest") do
    # Get package info (JSON)
    url = "#{@base_url}/package/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        # body is a map of version => {normal-version, ...}
        all_versions = Map.keys(body) |> Enum.sort(:desc)

        target_version = if version == "latest" do
          List.first(all_versions)
        else
          version
        end

        # Fetch cabal metadata for the specific version
        {description, license, deps, homepage, authors} = fetch_cabal_metadata(name, target_version)

        {:ok, parse_package(name, target_version, description, license, deps, homepage, authors, body)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Hackage returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_cabal_metadata(name, version) do
    url = "#{@base_url}/package/#{URI.encode(name)}-#{version}/#{URI.encode(name)}.cabal"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        parse_cabal(body)
      {:ok, body} when is_binary(body) ->
        parse_cabal(body)
      _ ->
        {nil, nil, %{}, nil, []}
    end
  end

  defp parse_cabal(content) do
    lines = String.split(content, "\n")

    # Extract top-level fields
    description = extract_field(lines, "description")
    license = extract_field(lines, "license")
    homepage = extract_field(lines, "homepage")
    author = extract_field(lines, "author")
    authors = if author, do: String.split(author, ",") |> Enum.map(&String.trim/1), else: []

    # Extract build-depends
    deps = extract_build_depends(lines)

    {description, license, deps, homepage, authors}
  end

  defp extract_field(lines, field_name) do
    pattern = String.downcase(field_name) <> ":"

    Enum.find_value(lines, fn line ->
      lower = String.downcase(String.trim(line))
      if String.starts_with?(lower, pattern) do
        line
        |> String.trim()
        |> String.split(":", parts: 2)
        |> List.last()
        |> String.trim()
        |> case do
          "" -> nil
          val -> val
        end
      end
    end)
  end

  defp extract_build_depends(lines) do
    # Find build-depends: sections and extract dependency names
    lines
    |> Enum.reduce({false, []}, fn line, {in_deps, deps} ->
      trimmed = String.trim(line)
      lower = String.downcase(trimmed)

      cond do
        String.starts_with?(lower, "build-depends:") ->
          # Inline deps after the colon
          rest = String.split(trimmed, ":", parts: 2) |> List.last() |> String.trim()
          new_deps = parse_dep_line(rest)
          {true, deps ++ new_deps}

        in_deps and (String.starts_with?(trimmed, " ") or String.starts_with?(trimmed, ",")) ->
          new_deps = parse_dep_line(trimmed)
          {true, deps ++ new_deps}

        in_deps and trimmed != "" ->
          # Reached a new field
          {false, deps}

        true ->
          {in_deps, deps}
      end
    end)
    |> elem(1)
    |> Enum.reject(fn {name, _} -> name in @ghc_builtins end)
    |> Map.new()
  end

  defp parse_dep_line(line) do
    line
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn s -> s == "" end)
    |> Enum.map(fn dep ->
      # Parse "package-name >=1.0 && <2.0" format
      # Also handle "package-name>=1.0" (no space before constraint)
      dep = String.trim(dep)

      # Split on first space, or on first constraint operator character
      {name, constraint} = cond do
        String.contains?(dep, " ") ->
          case String.split(dep, " ", parts: 2) do
            [n, c] -> {String.trim(n), String.trim(c)}
            [n] -> {String.trim(n), ">= 0"}
          end

        Regex.match?(~r/[><=]/, dep) ->
          case Regex.split(~r/(?=[><=])/, dep, parts: 2) do
            [n, c] -> {String.trim(n), String.trim(c)}
            [n] -> {String.trim(n), ">= 0"}
          end

        true ->
          {dep, ">= 0"}
      end

      {name, constraint}
    end)
    |> Enum.reject(fn {name, _} -> name == "" end)
  end

  @doc """
  Search for packages on Hackage.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/packages/search?terms=#{URI.encode(query)}"
    headers = [{"accept", "application/json"}]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
          |> Enum.take(limit)
          |> Enum.map(fn pkg ->
            %{
              name: pkg["name"],
              version: nil,
              description: pkg["synopsis"],
              downloads: 0
            }
          end)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Hackage search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on Hackage.
  """
  def exists?(name) do
    url = "#{@base_url}/package/#{URI.encode(name)}.json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a package.
  """
  def versions(name) do
    url = "#{@base_url}/package/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        versions = Map.keys(body) |> Enum.sort(:desc)
        {:ok, versions}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@base_url}/package/#{name}-#{version}/#{name}-#{version}.tar.gz"}
  end

  # Parsers

  defp parse_package(name, version, description, license, deps, homepage, authors, _raw) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :hackage,
      registry_url: "#{@base_url}/package/#{name}",
      tarball_url: "#{@base_url}/package/#{name}-#{version}/#{name}-#{version}.tar.gz",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: nil,
        authors: authors,
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :hackage,
        raw_manifest: %{}
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
