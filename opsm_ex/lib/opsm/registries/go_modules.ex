# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.GoModules do
  @moduledoc """
  Go module proxy API client.
  https://proxy.golang.org/
  Uses the Go module proxy protocol (GOPROXY).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @proxy_url "https://proxy.golang.org"
  @pkg_url "https://pkg.go.dev"

  @doc """
  Fetch module metadata from the Go proxy.
  """
  def fetch_package(name, version \\ "latest") do
    # Go modules use paths like "github.com/gin-gonic/gin"
    encoded = encode_module_path(name)

    target_version =
      if version == "latest" do
        fetch_latest_version(encoded)
      else
        version
      end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Fetch version info
        url = "#{@proxy_url}/#{encoded}/@v/#{ver}.info"

        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            deps = fetch_go_mod_deps(encoded, ver)
            ziphash = fetch_ziphash(name, ver)
            {:ok, parse_module(name, body, ver, deps, ziphash)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Go proxy returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(encoded) do
    url = "#{@proxy_url}/#{encoded}/@latest"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"Version" => version}} ->
        version

      _ ->
        # Fallback: get version list
        case versions_internal(encoded) do
          {:ok, [latest | _]} -> latest
          _ -> nil
        end
    end
  end

  defp fetch_go_mod_deps(encoded, version) do
    url = "#{@proxy_url}/#{encoded}/@v/#{version}.mod"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        parse_go_mod(body)

      {:ok, body} when is_binary(body) ->
        parse_go_mod(body)

      _ ->
        %{}
    end
  end

  defp parse_go_mod(content) do
    # Parse require directives from go.mod
    # Format: require ( \n module version \n )
    # Or: require module version
    content
    |> String.split("\n")
    |> Enum.reduce({false, %{}}, fn line, {in_require, deps} ->
      trimmed = String.trim(line)

      cond do
        trimmed == "require (" ->
          {true, deps}

        trimmed == ")" and in_require ->
          {false, deps}

        in_require and trimmed != "" and not String.starts_with?(trimmed, "//") ->
          case String.split(trimmed) do
            [mod, ver | _] ->
              # Skip indirect dependencies
              if String.contains?(trimmed, "// indirect") do
                {true, deps}
              else
                # Go MVS: versions are minimum versions, not exact
                # Strip quotes from module names (older go.mod format)
                mod = String.trim(mod, "\"")
                ver = String.trim(ver, "\"")
                {true, Map.put(deps, mod, ">= #{ver}")}
              end

            _ ->
              {true, deps}
          end

        String.starts_with?(trimmed, "require ") ->
          case String.split(trimmed) do
            ["require", mod, ver | _] ->
              mod = String.trim(mod, "\"")
              ver = String.trim(ver, "\"")
              {false, Map.put(deps, mod, ">= #{ver}")}

            _ ->
              {false, deps}
          end

        true ->
          {in_require, deps}
      end
    end)
    |> elem(1)
  end

  @doc """
  Search for Go modules.
  Uses pkg.go.dev search (no official search API on proxy).
  Falls back to checking if the module exists on the proxy.
  """
  def search(query, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 20)

    # The Go proxy has no search API. Check if the query is a direct module path.
    encoded = encode_module_path(query)

    case VerifiedHttp.get_json("#{@proxy_url}/#{encoded}/@latest", receive_timeout: 10_000) do
      {:ok, %{"Version" => version}} ->
        {:ok, [%{name: query, version: version, description: "Go module", downloads: 0}]}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Check if a Go module exists.
  """
  def exists?(name) do
    encoded = encode_module_path(name)
    url = "#{@proxy_url}/#{encoded}/@latest"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Go module.
  """
  def versions(name) do
    encoded = encode_module_path(name)
    versions_internal(encoded)
  end

  defp versions_internal(encoded) do
    url = "#{@proxy_url}/#{encoded}/@v/list"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        versions = body |> String.split("\n", trim: true) |> Enum.reverse()

        if versions == [] do
          # Some Go modules only have pseudo-versions (no tags)
          # Fall back to @latest
          fetch_latest_as_list(encoded)
        else
          {:ok, versions}
        end

      {:ok, body} when is_binary(body) ->
        versions = body |> String.split("\n", trim: true) |> Enum.reverse()

        if versions == [] do
          fetch_latest_as_list(encoded)
        else
          {:ok, versions}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_latest_as_list(encoded) do
    case VerifiedHttp.get_json("#{@proxy_url}/#{encoded}/@latest", receive_timeout: 10_000) do
      {:ok, %{"Version" => version}} -> {:ok, [version]}
      _ -> {:ok, []}
    end
  end

  @doc """
  Get zip URL for a specific version.
  """
  def tarball_url(name, version) do
    encoded = encode_module_path(name)
    {:ok, "#{@proxy_url}/#{encoded}/@v/#{version}.zip"}
  end

  # Go module path encoding:
  # Uppercase letters are encoded as !lowercase
  defp encode_module_path(path) do
    path
    |> String.graphemes()
    |> Enum.map(fn char ->
      if char >= "A" and char <= "Z" do
        "!" <> String.downcase(char)
      else
        char
      end
    end)
    |> Enum.join()
  end

  @sum_db "https://sum.golang.org"

  defp fetch_ziphash(name, version) do
    # Use the Go checksum database (sum.golang.org) for zip hash
    url = "#{@sum_db}/lookup/#{name}@#{version}"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        parse_sum_db_hash(body, name, version)

      {:ok, body} when is_binary(body) ->
        parse_sum_db_hash(body, name, version)

      _ ->
        nil
    end
  end

  # Parse sum.golang.org lookup response for the zip hash (h1: format)
  # Format: "module version h1:<base64>\nmodule version/go.mod h1:<base64>\n..."
  # We want the first line (zip hash), not the go.mod hash
  defp parse_sum_db_hash(body, name, version) do
    body
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      prefix = "#{name} #{version} h1:"

      if String.starts_with?(line, prefix) do
        "h1:" <> _ = String.trim_leading(line, "#{name} #{version} ")
        parse_h1_hash(String.trim(line) |> String.split(" ") |> List.last())
      end
    end)
  end

  # Go h1 hash format: "h1:<base64-encoded-sha256>"
  # Convert to hex-encoded SHA256 for compatibility with our checksum system
  defp parse_h1_hash("h1:" <> b64_hash) do
    b64_clean = String.trim_trailing(b64_hash, "=") |> pad_base64()

    case Base.decode64(b64_clean) do
      {:ok, raw_hash} -> Base.encode16(raw_hash, case: :lower)
      :error -> nil
    end
  end

  defp parse_h1_hash(_), do: nil

  defp pad_base64(s) do
    case rem(String.length(s), 4) do
      0 -> s
      n -> s <> String.duplicate("=", 4 - n)
    end
  end

  # Parsers

  defp parse_module(name, info, version, deps, ziphash) do
    %ResolvedPackage{
      package: name,
      version: version,
      forth: :go,
      registry_url: "#{@pkg_url}/#{name}",
      tarball_url: "#{@proxy_url}/#{encode_module_path(name)}/@v/#{version}.zip",
      checksum: ziphash,
      checksum_algo: if(ziphash, do: :sha256, else: nil),
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: nil,
        license: nil,
        homepage: "#{@pkg_url}/#{name}",
        repository:
          if(String.starts_with?(name, "github.com/"), do: "https://#{name}", else: nil),
        authors: [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :go,
        raw_manifest: info
      },
      attestations: [],
      resolved_deps: []
    }
  end
end
