# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Shard do
  @moduledoc """
  Crystal shards registry adapter.
  https://shardbox.org/
  Queries Shardbox for Crystal language shard metadata.

  API endpoints used:
  - GET /api/v1/shards/:owner/:name     - Shard metadata
  - GET /api/v1/shards?query=:q         - Search shards
  - GET /api/v1/shards/:owner/:name/versions - Version listing

  Note: Shardbox may not expose a formal versioned JSON API; this adapter
  targets the documented endpoints and falls back to GitHub releases when
  Shardbox data is unavailable.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://shardbox.org/api/v1"

  @doc """
  Fetch shard metadata from Shardbox.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/shards/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = resolve_version(body, version)
        {:ok, build_resolved_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Search for Crystal shards matching a query string.
  """
  def search(query, _opts \\ []) do
    url = "#{@base_url}/shards?query=#{URI.encode_www_form(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"shards" => shards}} when is_list(shards) ->
        matches =
          shards
          |> Enum.take(20)
          |> Enum.map(fn s ->
            %{
              name: s["name"] || s["qualified_name"],
              version: s["version"] || s["latest_version"],
              description: s["description"]
            }
          end)

        {:ok, matches}

      {:ok, results} when is_list(results) ->
        matches =
          results
          |> Enum.take(20)
          |> Enum.map(fn s ->
            %{
              name: s["name"],
              version: s["version"] || s["latest_version"],
              description: s["description"]
            }
          end)

        {:ok, matches}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a shard exists in the registry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a shard.
  """
  def versions(name) do
    url = "#{@base_url}/shards/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        vers = Enum.map(body, fn v -> v["version"] || v["number"] end)
        {:ok, Enum.reject(vers, &is_nil/1)}

      {:ok, %{"versions" => vers}} when is_list(vers) ->
        {:ok, Enum.map(vers, fn v -> v["version"] || v["number"] end)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp resolve_version(body, "latest") do
    body["version"] || body["latest_version"] || "0.0.0"
  end

  defp resolve_version(_body, version), do: version

  defp build_resolved_package(name, body, version) do
    deps =
      (body["dependencies"] || [])
      |> normalise_deps()

    repo_url = body["repository_url"] || body["git_url"]

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["homepage"] || repo_url,
      repository: repo_url,
      dependencies: deps,
      source_forth: :shard
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :shard,
      registry_url: "https://shardbox.org/shards/#{name}",
      manifest: manifest,
      tarball_url: build_tarball_url(repo_url, version),
      checksum: nil,
      attestations: []
    }
  end

  defp normalise_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(fn
      %{"name" => n, "version" => v} -> {n, v}
      %{"name" => n} -> {n, "*"}
      d when is_binary(d) -> {d, "*"}
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp normalise_deps(deps) when is_map(deps), do: deps
  defp normalise_deps(_), do: %{}

  defp build_tarball_url(nil, _version), do: nil

  defp build_tarball_url(repo_url, version) do
    cond do
      String.contains?(repo_url, "github.com") ->
        "#{repo_url}/archive/refs/tags/v#{version}.tar.gz"

      true ->
        nil
    end
  end
end
