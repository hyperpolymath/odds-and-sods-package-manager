# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Snap do
  @moduledoc """
  Snapcraft (Snap Store) registry adapter.
  https://api.snapcraft.io/docs/
  Queries the Snap Store API for snap package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://api.snapcraft.io/v2/snaps/info"

  @doc """
  Fetch snap package metadata from the Snap Store.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{name}"
    headers = [
      {"Snap-Device-Series", "16"},
      {"Snap-Device-Architecture", "amd64"}
    ]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} ->
        channel_map = body["channel-map"] || []
        stable = Enum.find(channel_map, fn c ->
          get_in(c, ["channel", "name"]) == "stable"
        end)

        ver = if version == "latest" do
          if stable, do: stable["version"], else: "0.0.0"
        else
          version
        end

        {:ok, parse_snap(name, body, ver, stable)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_snap(name, body, version, stable_channel) do
    snap = body["snap"] || %{}

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: snap["summary"] || snap["description"],
      license: snap["license"],
      homepage: snap["website"],
      repository: snap["contact"],
      dependencies: %{}
    }

    download_url = if stable_channel do
      get_in(stable_channel, ["download", "url"])
    end

    download_sha = if stable_channel do
      get_in(stable_channel, ["download", "sha3-384"])
    end

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :snap,
      manifest: manifest,
      tarball_url: download_url,
      checksum: download_sha,
      checksum_algo: if(download_sha, do: :"sha3-384"),
      attestations: [],
    }
  end

  @doc """
  Get available versions across channels.
  """
  def get_versions(name) do
    url = "#{@api_url}/#{name}"
    headers = [{"Snap-Device-Series", "16"}, {"Snap-Device-Architecture", "amd64"}]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = (body["channel-map"] || [])
                   |> Enum.map(fn c -> c["version"] end)
                   |> Enum.reject(&is_nil/1)
                   |> Enum.uniq()
        {:ok, versions}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for snaps in the Snap Store.
  """
  def search(query, _opts \\ []) do
    url = "https://api.snapcraft.io/v2/snaps/find?q=#{URI.encode(query)}&fields=title,summary,version"
    headers = [{"Snap-Device-Series", "16"}]

    case VerifiedHttp.get_json(url, headers: headers, receive_timeout: 10_000) do
      {:ok, body} ->
        results = (body["results"] || [])
        |> Enum.take(20)
        |> Enum.map(fn s ->
          snap = s["snap"] || %{}
          %{name: s["name"], version: s["version"], description: snap["summary"]}
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  def versions(name), do: get_versions(name)
end
