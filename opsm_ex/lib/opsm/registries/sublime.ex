# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Sublime do
  @moduledoc """
  Sublime Text Package Control registry adapter.
  https://packagecontrol.io/
  Queries the Package Control API for Sublime Text package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://packagecontrol.io"

  @doc """
  Fetch package metadata from Package Control.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/packages/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          extract_latest_version(body)
        else
          version
        end
        {:ok, parse_sublime_package(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_latest_version(body) do
    releases = body["releases"] || body["versions"] || []
    case releases do
      [latest | _] ->
        latest["version"] || latest["date"] || "0.0.0"
      _ ->
        body["version"] || "0.0.0"
    end
  end

  defp parse_sublime_package(name, body, version) do
    deps = (body["dependencies"] || [])
           |> Enum.map(fn
             d when is_binary(d) -> {d, "*"}
             d when is_map(d) -> {d["name"] || "", "*"}
             _ -> nil
           end)
           |> Enum.reject(&is_nil/1)
           |> Enum.reject(fn {n, _} -> n == "" end)
           |> Map.new()

    labels = (body["labels"] || []) |> Enum.join(", ")
    description = body["description"] || ""
    full_description = if labels != "" do
      "#{description} [#{labels}]"
    else
      description
    end

    homepage = body["homepage"] || "#{@api_url}/packages/#{URI.encode(name)}"
    repository = extract_repository(body)

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: full_description,
      license: nil,
      homepage: homepage,
      repository: repository,
      dependencies: deps
    }

    tarball_url = build_download_url(body, repository)

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :sublime,
      manifest: manifest,
      tarball_url: tarball_url,
      checksum: nil,
      attestations: [],
    }
  end

  defp extract_repository(body) do
    case body["sources"] || body["repositories"] do
      [repo | _] when is_binary(repo) -> repo
      [repo | _] when is_map(repo) -> repo["url"]
      _ -> body["homepage"]
    end
  end

  defp build_download_url(body, repository) do
    releases = body["releases"] || body["versions"] || []
    case releases do
      [latest | _] ->
        latest["url"] || latest["download_url"]
      _ ->
        # Attempt to build a GitHub archive URL from the repository
        case repository do
          "https://github.com/" <> _ = repo ->
            "#{repo}/archive/refs/heads/master.zip"
          _ -> nil
        end
    end
  end

  @doc """
  Get available versions of a Sublime Text package.
  """
  def get_versions(name) do
    url = "#{@api_url}/packages/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        releases = body["releases"] || body["versions"] || []
        versions_list = releases
                        |> Enum.map(fn r -> r["version"] || r["date"] end)
                        |> Enum.reject(&is_nil/1)
                        |> Enum.uniq()

        if versions_list == [] do
          case fetch_package(name) do
            {:ok, pkg} -> {:ok, [pkg.version]}
            {:error, _} = err -> err
          end
        else
          {:ok, versions_list}
        end

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages on Package Control.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search/#{URI.encode(query)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: extract_latest_version(pkg),
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, %{"packages" => packages}} when is_list(packages) ->
        results = packages
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: nil,
            description: pkg["description"]
          }
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a package exists on Package Control.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for a package.
  """
  def versions(name), do: get_versions(name)
end
