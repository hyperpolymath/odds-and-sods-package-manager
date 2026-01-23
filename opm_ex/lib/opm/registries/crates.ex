# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Registries.Crates do
  @moduledoc """
  Crates.io Registry API client.
  https://crates.io/api/v1
  """

  alias Opm.Types.{ManifestFormat, ResolvedPackage}
  alias Opm.Verified.Http, as: VerifiedHttp

  @base_url "https://crates.io/api/v1"
  @download_base "https://static.crates.io/crates"

  # crates.io requires a user-agent
  @headers [{"user-agent", "opm/0.1.0 (https://github.com/hyperpolymath/opm)"}]

  @doc """
  Fetch crate metadata from crates.io.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@base_url}/crates/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        crate = body["crate"]
        versions = body["versions"] || []

        target_version = if version == "latest" do
          crate["newest_version"] || crate["max_version"]
        else
          version
        end

        version_info = Enum.find(versions, fn v -> v["num"] == target_version end)
        {:ok, parse_crate(crate, version_info, target_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "crates.io returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for crates on crates.io.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@base_url}/crates?q=#{URI.encode(query)}&per_page=#{limit}"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        crates = body["crates"] || []
        {:ok, Enum.map(crates, &parse_search_result/1)}

      {:error, %{status: status}} ->
        {:error, "crates.io search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a crate exists.
  """
  def exists?(name) do
    url = "#{@base_url}/crates/#{URI.encode(name)}"

    case VerifiedHttp.get(url, headers: @headers, receive_timeout: 5_000) do
      {:ok, _response} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a crate.
  """
  def versions(name) do
    url = "#{@base_url}/crates/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        versions = body["versions"] || []
        {:ok, Enum.map(versions, & &1["num"]) |> Enum.reject(&is_nil/1)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get dependencies for a specific version.
  """
  def dependencies(name, version) do
    url = "#{@base_url}/crates/#{URI.encode(name)}/#{version}/dependencies"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        deps = body["dependencies"] || []
        {:ok, parse_dependencies(deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, "#{@download_base}/#{name}/#{name}-#{version}.crate"}
  end

  # Parsers

  defp parse_crate(crate, version_info, version) do
    checksum = if version_info, do: version_info["checksum"], else: nil

    %ResolvedPackage{
      package: crate["id"] || crate["name"],
      version: version,
      forth: :cargo,
      registry_url: "https://crates.io",
      tarball_url: "#{@download_base}/#{crate["id"]}/#{crate["id"]}-#{version}.crate",
      checksum: checksum,
      checksum_algo: :sha256,
      manifest: %ManifestFormat{
        name: crate["id"] || crate["name"],
        version: version,
        description: crate["description"],
        license: version_info["license"],
        homepage: crate["homepage"],
        repository: crate["repository"],
        authors: [],  # crates.io doesn't return authors in crate endpoint
        keywords: crate["keywords"] || [],
        dependencies: %{},  # Fetched separately
        dev_dependencies: %{},
        source_forth: :cargo,
        raw_manifest: crate
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_search_result(crate) do
    %{
      name: crate["id"] || crate["name"],
      version: crate["newest_version"] || crate["max_version"],
      description: crate["description"],
      keywords: crate["keywords"] || [],
      downloads: crate["downloads"],
      recent_downloads: crate["recent_downloads"]
    }
  end

  defp parse_dependencies(deps) do
    deps
    |> Enum.group_by(& &1["kind"])
    |> Enum.map(fn {kind, deps_list} ->
      dep_map = deps_list
        |> Enum.map(fn d -> {d["crate_id"], d["req"]} end)
        |> Map.new()
      {kind, dep_map}
    end)
    |> Map.new()
  end
end
