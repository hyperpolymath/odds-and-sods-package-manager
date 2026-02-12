# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Elm do
  @moduledoc """
  Elm package registry adapter.
  https://package.elm-lang.org
  Uses the official Elm package API.
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://package.elm-lang.org"

  def fetch_package(name, version \\ "latest") do
    target_version = if version == "latest" do
      case versions(name) do
        {:ok, [latest | _]} -> latest
        _ -> nil
      end
    else
      version
    end

    case target_version do
      nil -> {:error, :not_found}
      ver ->
        url = "#{@api_url}/packages/#{name}/#{ver}/elm.json"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            deps = extract_deps(body)
            {:ok, %ResolvedPackage{
              package: name,
              version: ver,
              forth: :elm,
              registry_url: "#{@api_url}/packages/#{name}/#{ver}",
              tarball_url: "#{@api_url}/packages/#{name}/#{ver}/endpoint.json",
              checksum: nil,
              checksum_algo: nil,
              manifest: %ManifestFormat{
                name: name,
                version: ver,
                description: body["summary"],
                license: body["license"],
                homepage: "#{@api_url}/packages/#{name}",
                repository: nil,
                authors: [],
                keywords: [],
                dependencies: deps,
                dev_dependencies: %{},
                source_forth: :elm,
                raw_manifest: body
              },
              attestations: [],
              resolved_deps: []
            }}

          {:error, :not_found} -> {:error, :not_found}
          {:error, %{status: 404}} -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def search(query, _opts \\ []) do
    # Elm has no search API — fetch all packages and filter
    url = "#{@api_url}/search.json"
    case VerifiedHttp.get_json(url, receive_timeout: 15_000) do
      {:ok, packages} when is_list(packages) ->
        results = packages
          |> Enum.filter(fn p ->
            name = p["name"] || ""
            summary = p["summary"] || ""
            String.contains?(String.downcase(name), String.downcase(query)) ||
            String.contains?(String.downcase(summary), String.downcase(query))
          end)
          |> Enum.take(20)
          |> Enum.map(fn p ->
            %{name: p["name"], version: nil, description: p["summary"], downloads: 0}
          end)
        {:ok, results}
      _ -> {:ok, []}
    end
  end

  def exists?(name) do
    url = "#{@api_url}/packages/#{name}/releases.json"
    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def versions(name) do
    url = "#{@api_url}/packages/#{name}/releases.json"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, releases} when is_list(releases) ->
        vers = Enum.map(releases, fn r -> r["version"] end)
          |> Enum.reject(&is_nil/1)
        {:ok, vers}
      _ -> {:error, :not_found}
    end
  end

  def tarball_url(name, version) do
    {:ok, "#{@api_url}/packages/#{name}/#{version}/endpoint.json"}
  end

  defp extract_deps(body) do
    deps = body["dependencies"] || %{}
    Enum.into(deps, %{}, fn {name, constraint} ->
      {name, constraint}
    end)
  end
end
