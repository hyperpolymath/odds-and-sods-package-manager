# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Bower do
  @moduledoc """
  Bower registry adapter.
  https://registry.bower.io/
  Queries the Bower package registry for front-end web components.
  Note: Bower is largely deprecated in favour of npm/yarn, but many
  legacy projects still reference Bower packages.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @registry_url "https://registry.bower.io/packages"

  @doc """
  Fetch package metadata from the Bower registry.
  Bower registry only stores name -> git URL mappings, so we resolve
  the git endpoint and fetch bower.json from the repository.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@registry_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        repo_url = body["url"]
        github_owner_repo = extract_github_path(repo_url)

        case fetch_bower_json(github_owner_repo, version) do
          {:ok, bower_json, resolved_ver} ->
            {:ok, parse_bower(name, bower_json, resolved_ver, repo_url)}

          {:error, _} ->
            # Fall back to basic info from the registry
            {:ok, parse_bower_basic(name, body, version)}
        end

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_github_path(url) when is_binary(url) do
    url
    |> String.replace(~r{^https?://github\.com/}, "")
    |> String.replace(~r{\.git$}, "")
    |> String.trim_trailing("/")
  end

  defp extract_github_path(_), do: nil

  defp fetch_bower_json(nil, _version), do: {:error, :no_github_path}

  defp fetch_bower_json(owner_repo, version) do
    ref = if version == "latest", do: "HEAD", else: "v#{version}"
    url = "https://raw.githubusercontent.com/#{owner_repo}/#{ref}/bower.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        resolved_ver = body["version"] || version
        ver = if resolved_ver == "latest", do: "0.0.0", else: resolved_ver
        {:ok, body, ver}

      {:error, _} = err -> err
    end
  end

  defp parse_bower(name, bower_json, version, repo_url) do
    deps = bower_json["dependencies"] || %{}
    dev_deps = bower_json["devDependencies"] || %{}

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: bower_json["description"],
      license: normalize_license(bower_json["license"]),
      homepage: bower_json["homepage"],
      repository: repo_url,
      authors: normalize_authors(bower_json["authors"]),
      keywords: bower_json["keywords"] || [],
      dependencies: deps,
      dev_dependencies: dev_deps,
      source_forth: :bower,
      raw_manifest: bower_json
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :bower,
      registry_url: "https://registry.bower.io",
      manifest: manifest,
      tarball_url: repo_url,
      checksum: nil,
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_bower_basic(name, body, version) do
    ver = if version == "latest", do: "0.0.0", else: version

    manifest = %ManifestFormat{
      name: name,
      version: ver,
      description: nil,
      license: nil,
      homepage: nil,
      repository: body["url"],
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: ver,
      forth: :bower,
      registry_url: "https://registry.bower.io",
      manifest: manifest,
      tarball_url: body["url"],
      checksum: nil,
      attestations: [],
      resolved_deps: []
    }
  end

  defp normalize_license(license) when is_binary(license), do: license
  defp normalize_license(licenses) when is_list(licenses), do: Enum.join(licenses, " OR ")
  defp normalize_license(_), do: nil

  defp normalize_authors(authors) when is_list(authors) do
    Enum.map(authors, fn
      a when is_binary(a) -> a
      a when is_map(a) -> a["name"] || "Unknown"
      _ -> "Unknown"
    end)
  end

  defp normalize_authors(_), do: []

  @doc """
  Search for packages in the Bower registry.
  """
  def search(query, _opts \\ []) do
    url = "#{@registry_url}/search/#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        parsed = results
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: nil,
            description: pkg["url"]
          }
        end)
        {:ok, parsed}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists in the Bower registry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions. Bower does not expose a versions endpoint
  directly, so we return the resolved version from the package.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end
end
