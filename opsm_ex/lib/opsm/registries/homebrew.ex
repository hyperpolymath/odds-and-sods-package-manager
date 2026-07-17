# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.Homebrew do
  @moduledoc """
  Homebrew registry adapter.
  https://formulae.brew.sh/api/
  Queries Homebrew formulae and casks via the JSON API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @formula_api "https://formulae.brew.sh/api/formula"
  @cask_api "https://formulae.brew.sh/api/cask"

  @doc """
  Fetch package metadata from Homebrew.
  Tries formula first, then cask.
  """
  def fetch_package(name, version \\ "latest") do
    case fetch_formula(name, version) do
      {:ok, _} = result -> result
      {:error, :not_found} -> fetch_cask(name, version)
      {:error, _} = err -> err
    end
  end

  defp fetch_formula(name, version) do
    url = "#{@formula_api}/#{name}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: get_in(body, ["versions", "stable"]),
            else: version

        {:ok, parse_formula(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_cask(name, version) do
    url = "#{@cask_api}/#{name}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest",
            do: body["version"],
            else: version

        {:ok, parse_cask(name, body, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_formula(name, body, version) do
    deps =
      (body["dependencies"] || [])
      |> Enum.map(fn d -> {d, "*"} end)
      |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["desc"],
      license: body["license"],
      homepage: body["homepage"],
      repository: get_in(body, ["urls", "stable", "url"]),
      dependencies: deps
    }

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :homebrew,
      manifest: manifest,
      tarball_url: get_in(body, ["urls", "stable", "url"]),
      checksum: nil,
      attestations: []
    }
  end

  defp parse_cask(name, body, version) do
    manifest = %ManifestFormat{
      name: name,
      version: version || "0.0.0",
      description: body["desc"],
      license: nil,
      homepage: body["homepage"],
      repository: nil,
      dependencies: %{}
    }

    url =
      case body["url"] do
        url when is_binary(url) -> url
        _ -> nil
      end

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :homebrew,
      manifest: manifest,
      tarball_url: url,
      checksum: body["sha256"],
      checksum_algo: if(body["sha256"], do: :sha256),
      attestations: []
    }
  end

  @doc """
  Get all available versions of a formula.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for packages matching a query.
  """
  def search(query, _opts \\ []) do
    url = "#{@formula_api}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 30_000) do
      {:ok, formulae} when is_list(formulae) ->
        matches =
          formulae
          |> Enum.filter(fn f ->
            name = f["name"] || ""
            desc = f["desc"] || ""

            String.contains?(String.downcase(name), String.downcase(query)) or
              String.contains?(String.downcase(desc), String.downcase(query))
          end)
          |> Enum.take(20)
          |> Enum.map(fn f ->
            %{name: f["name"], version: get_in(f, ["versions", "stable"]), description: f["desc"]}
          end)

        {:ok, matches}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get all versions for a package.
  """
  def versions(name), do: get_versions(name)
end
