# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.CargoBinstall do
  @moduledoc """
  Cargo binary install registry adapter.
  Combines crates.io metadata with cargo-quickinstall prebuilt binaries
  (https://github.com/cargo-bins/cargo-quickinstall) to provide
  binary-first Rust package installation, falling back to source builds.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @crates_api "https://crates.io/api/v1"
  @quickinstall_api "https://warehouse-clerk-tmp.vercel.app/api/crate"
  @quickinstall_dl "https://github.com/cargo-bins/cargo-quickinstall/releases/download"
  @crates_dl "https://static.crates.io/crates"

  @headers [{"user-agent", "opsm/0.1.0 (https://github.com/hyperpolymath/opsm)"}]

  @doc """
  Fetch crate metadata, checking for prebuilt binary availability.
  Queries crates.io for metadata and cargo-quickinstall for binaries.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@crates_api}/crates/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        crate = body["crate"] || %{}
        versions_list = body["versions"] || []

        ver = if version == "latest" do
          crate["newest_version"] || crate["max_version"] || "0.0.0"
        else
          version
        end

        version_info = Enum.find(versions_list, fn v -> v["num"] == ver end)

        # Check for prebuilt binary availability
        binary_info = check_quickinstall(name, ver)

        {:ok, parse_binstall(name, crate, version_info, ver, binary_info)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_quickinstall(name, version) do
    # Detect platform for binary lookup
    target = detect_target_triple()
    url = "#{@quickinstall_api}/#{URI.encode(name)}/#{version}"

    case VerifiedHttp.get_json(url, receive_timeout: 5_000) do
      {:ok, body} ->
        targets = body["targets"] || []
        matching = Enum.find(targets, fn t ->
          t["target"] == target || String.contains?(t["target"] || "", target)
        end)
        if matching do
          %{
            binary_url: matching["url"] || build_quickinstall_url(name, version, target),
            binary_hash: matching["sha256"],
            target: target,
            prebuilt: true
          }
        else
          %{prebuilt: false, target: target}
        end

      {:error, _} ->
        # Quickinstall unavailable; source-only install
        %{prebuilt: false, target: target}
    end
  end

  defp detect_target_triple do
    case :os.type() do
      {:unix, :linux} -> "x86_64-unknown-linux-gnu"
      {:unix, :darwin} -> "x86_64-apple-darwin"
      {:win32, _} -> "x86_64-pc-windows-msvc"
      _ -> "x86_64-unknown-linux-gnu"
    end
  end

  defp build_quickinstall_url(name, version, target) do
    "#{@quickinstall_dl}/#{name}-#{version}/#{name}-#{version}-#{target}.tar.gz"
  end

  defp parse_binstall(name, crate, version_info, version, binary_info) do
    checksum = if binary_info[:prebuilt] do
      binary_info[:binary_hash]
    else
      if version_info, do: version_info["checksum"], else: nil
    end

    tarball = if binary_info[:prebuilt] do
      binary_info[:binary_url]
    else
      "#{@crates_dl}/#{name}/#{name}-#{version}.crate"
    end

    # Fetch dependencies from the version-specific endpoint
    deps = fetch_deps(name, version)

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: crate["description"],
      license: if(version_info, do: version_info["license"], else: nil),
      homepage: crate["homepage"],
      repository: crate["repository"],
      authors: [],
      keywords: (crate["keywords"] || []) ++ binstall_keywords(binary_info),
      dependencies: deps,
      source_forth: :cargo_binstall,
      raw_manifest: Map.merge(crate, %{"binstall" => binary_info})
    }

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :cargo_binstall,
      registry_url: "https://crates.io",
      manifest: manifest,
      tarball_url: tarball,
      checksum: checksum,
      checksum_algo: if(checksum, do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  defp binstall_keywords(%{prebuilt: true, target: target}), do: ["prebuilt-binary", target]
  defp binstall_keywords(_), do: ["source-build"]

  defp fetch_deps(name, version) do
    url = "#{@crates_api}/crates/#{URI.encode(name)}/#{version}/dependencies"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        (body["dependencies"] || [])
        |> Enum.filter(fn d -> d["kind"] == "normal" and not (d["optional"] || false) end)
        |> Enum.map(fn d -> {d["crate_id"], d["req"]} end)
        |> Map.new()

      _ -> %{}
    end
  end

  @doc """
  Search for crates on crates.io (binary-installable crates prioritised).
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@crates_api}/crates?q=#{URI.encode(query)}&per_page=#{limit}"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        results = (body["crates"] || [])
        |> Enum.map(fn crate ->
          %{
            name: crate["id"] || crate["name"],
            version: crate["newest_version"] || crate["max_version"],
            description: crate["description"]
          }
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a crate exists on crates.io.
  """
  def exists?(name) do
    url = "#{@crates_api}/crates/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a crate from crates.io.
  """
  def versions(name) do
    url = "#{@crates_api}/crates/#{URI.encode(name)}/versions"

    case VerifiedHttp.get_json(url, headers: @headers, receive_timeout: 10_000) do
      {:ok, body} ->
        vers = (body["versions"] || [])
               |> Enum.map(& &1["num"])
               |> Enum.reject(&is_nil/1)
        {:ok, vers}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end
end
