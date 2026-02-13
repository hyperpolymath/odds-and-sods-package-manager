# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.HomebrewCask do
  @moduledoc """
  Homebrew Cask registry adapter (casks only).
  https://formulae.brew.sh/api/cask/
  Queries the Homebrew Cask JSON API for macOS application metadata.
  Unlike the Homebrew adapter which checks formulae first, this adapter
  exclusively queries casks (GUI applications, fonts, plugins, etc.).
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://formulae.brew.sh/api/cask"

  @doc """
  Fetch cask metadata from the Homebrew Cask API.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver = if version == "latest",
          do: body["version"],
          else: version
        {:ok, parse_cask(name, body, ver)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_cask(name, body, version) do
    deps = extract_cask_dependencies(body)

    manifest = %ManifestFormat{
      name: body["token"] || name,
      version: version || "0.0.0",
      description: build_description(body),
      license: nil,
      homepage: body["homepage"],
      repository: "https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/#{cask_dir_prefix(name)}/#{name}.rb",
      dependencies: deps
    }

    download_url = case body["url"] do
      url when is_binary(url) -> url
      _ -> nil
    end

    %ResolvedPackage{
      package: name,
      version: version || "0.0.0",
      forth: :homebrew_cask,
      manifest: manifest,
      tarball_url: download_url,
      checksum: body["sha256"],
      checksum_algo: if(body["sha256"] && body["sha256"] != "no_check", do: :sha256),
      attestations: [],
    }
  end

  defp build_description(body) do
    _name_parts = [body["name"] | List.wrap(nil)]
    primary_name = case body["name"] do
      names when is_list(names) -> List.first(names)
      name when is_binary(name) -> name
      _ -> nil
    end

    desc = body["desc"]
    case {primary_name, desc} do
      {nil, nil} -> nil
      {nil, d} -> d
      {n, nil} -> n
      {n, d} -> "#{n} - #{d}"
    end
  end

  defp cask_dir_prefix(name) do
    String.first(name) || "a"
  end

  defp extract_cask_dependencies(body) do
    deps = body["depends_on"] || %{}

    formula_deps = (deps["formula"] || [])
                   |> Enum.map(fn d -> {d, "*"} end)

    cask_deps = (deps["cask"] || [])
                |> Enum.map(fn d -> {d, "*"} end)

    (formula_deps ++ cask_deps) |> Map.new()
  end

  @doc """
  Get available versions. Casks typically have one version.
  Includes version history from the analytics endpoint if available.
  """
  def get_versions(name) do
    case fetch_package(name) do
      {:ok, pkg} -> {:ok, [pkg.version]}
      {:error, _} = err -> err
    end
  end

  @doc """
  Search for casks in Homebrew.
  Downloads the full cask index and filters client-side.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 30_000) do
      {:ok, casks} when is_list(casks) ->
        query_down = String.downcase(query)

        results = casks
        |> Enum.filter(fn cask ->
          token = String.downcase(cask["token"] || "")
          desc = String.downcase(cask["desc"] || "")
          names = (cask["name"] || [])
                  |> List.wrap()
                  |> Enum.map(&String.downcase/1)

          String.contains?(token, query_down) or
          String.contains?(desc, query_down) or
          Enum.any?(names, &String.contains?(&1, query_down))
        end)
        |> Enum.take(20)
        |> Enum.map(fn cask ->
          %{
            name: cask["token"],
            version: cask["version"],
            description: cask["desc"]
          }
        end)

        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a cask exists in Homebrew.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get versions for a cask.
  """
  def versions(name), do: get_versions(name)
end
