# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Flatpak do
  @moduledoc """
  Flatpak (Flathub) registry adapter.
  https://flathub.org/api/v2/
  Queries the Flathub API for Flatpak application metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://flathub.org/api/v2"

  @doc """
  Fetch application metadata from Flathub.
  Name should be the app ID (e.g., "org.mozilla.firefox").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/appstream/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest" do
          releases = get_in(body, ["releases"]) || []
          case releases do
            [latest | _] -> latest["version"]
            _ -> "0.0.0"
          end
        else
          version
        end
        {:ok, parse_flatpak(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_flatpak(name, body, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["summary"],
      license: body["project_license"],
      homepage: get_in(body, ["urls", "homepage"]),
      repository: get_in(body, ["urls", "vcs_browser"]),
      dependencies: %{}
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :flatpak,
      manifest: manifest,
      tarball_url: nil,
      checksum: nil,
      attestations: [],
    }
  end

  @doc """
  Get available versions (releases) from Flathub.
  """
  def get_versions(name) do
    url = "#{@api_url}/appstream/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = (body["releases"] || [])
                   |> Enum.map(fn r -> r["version"] end)
                   |> Enum.reject(&is_nil/1)
        {:ok, versions}

      {:error, _} = err -> err
    end
  end

  @doc """
  Search for applications on Flathub.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search?q=#{URI.encode(query)}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
        |> Enum.take(20)
        |> Enum.map(fn app ->
          %{name: app["id"], version: nil, description: app["summary"]}
        end)
        {:ok, results}

      {:ok, %{"hits" => hits}} when is_list(hits) ->
        results = hits
        |> Enum.take(20)
        |> Enum.map(fn app ->
          %{name: app["app_id"] || app["id"], version: nil, description: app["summary"]}
        end)
        {:ok, results}

      {:ok, _} -> {:ok, []}
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
