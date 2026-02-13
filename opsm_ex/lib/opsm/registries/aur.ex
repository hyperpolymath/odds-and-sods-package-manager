# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Aur do
  @moduledoc """
  Arch User Repository (AUR) registry adapter.
  https://aur.archlinux.org/rpc/v5
  Queries the AUR RPC interface for package metadata, versions, and search.
  Supports both info lookups and keyword-based search.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://aur.archlinux.org/rpc/v5"

  @doc """
  Fetch package metadata from the AUR.
  Retrieves detailed package info via the AUR RPC v5 info endpoint.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/info?arg[]=#{URI.encode_www_form(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => [pkg_data | _]}} ->
        ver = if version == "latest" do
          pkg_data["Version"] || "0.0.0"
        else
          version
        end
        {:ok, parse_aur_package(name, pkg_data, ver)}

      {:ok, %{"results" => []}} ->
        {:error, :not_found}

      {:ok, %{"resultcount" => 0}} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "AUR returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on the AUR.
  Uses the AUR RPC v5 search endpoint with name-desc matching.
  Returns a list of matching packages with name, version, and description.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search/#{URI.encode_www_form(query)}?by=name-desc"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => results}} when is_list(results) ->
        parsed = results
        |> Enum.take(20)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["Name"],
            version: pkg["Version"],
            description: pkg["Description"]
          }
        end)
        {:ok, parsed}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on the AUR.
  """
  def exists?(name) do
    url = "#{@api_url}/info?arg[]=#{URI.encode_www_form(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"resultcount" => count}} when count > 0 -> true
      {:ok, %{"results" => [_ | _]}} -> true
      _ -> false
    end
  end

  @doc """
  Get all available versions of an AUR package.
  The AUR only provides the current version per package, so this returns
  a single-element list with the current version.
  """
  def versions(name) do
    url = "#{@api_url}/info?arg[]=#{URI.encode_www_form(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"results" => [pkg_data | _]}} ->
        ver = pkg_data["Version"]
        if ver, do: {:ok, [ver]}, else: {:ok, []}

      {:ok, %{"results" => []}} ->
        {:error, :not_found}

      {:ok, %{"resultcount" => 0}} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_aur_package(name, data, version) do
    deps = extract_dependencies(data)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: data["Description"],
      license: extract_license(data),
      homepage: data["URL"],
      repository: "https://aur.archlinux.org/#{name}.git",
      authors: extract_authors(data),
      keywords: data["Keywords"] || [],
      dependencies: deps,
      dev_dependencies: extract_make_deps(data),
      source_forth: :aur,
      raw_manifest: data
    }

    tarball_url = case data["URLPath"] do
      nil -> nil
      path -> "https://aur.archlinux.org#{path}"
    end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :aur,
      registry_url: "https://aur.archlinux.org/packages/#{name}",
      tarball_url: tarball_url,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_dependencies(data) do
    (data["Depends"] || [])
    |> Enum.reduce(%{}, fn dep, acc ->
      {dep_name, constraint} = parse_dep_string(dep)
      Map.put(acc, dep_name, constraint)
    end)
  end

  defp extract_make_deps(data) do
    (data["MakeDepends"] || [])
    |> Enum.reduce(%{}, fn dep, acc ->
      {dep_name, constraint} = parse_dep_string(dep)
      Map.put(acc, dep_name, constraint)
    end)
  end

  defp parse_dep_string(dep) when is_binary(dep) do
    # AUR deps can be "name>=version", "name=version", "name<version", or just "name"
    case Regex.run(~r/^([a-zA-Z0-9_.+-]+)([><=]+.+)?$/, dep) do
      [_, name, constraint] -> {name, constraint}
      [_, name] -> {name, "*"}
      _ -> {dep, "*"}
    end
  end

  defp parse_dep_string(_), do: {"unknown", "*"}

  defp extract_license(data) do
    case data["License"] do
      licenses when is_list(licenses) -> Enum.join(licenses, " AND ")
      license when is_binary(license) -> license
      _ -> nil
    end
  end

  defp extract_authors(data) do
    maintainer = data["Maintainer"]
    submitter = data["Submitter"]

    [maintainer, submitter]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(fn a -> a == "" end)
    |> Enum.uniq()
  end
end
