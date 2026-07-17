# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Storage.Ipfs do
  @moduledoc """
  IPFS (Kubo) storage backend for content-addressed tarball caching.

  Uses the Kubo HTTP RPC API:
  - POST /api/v0/add?pin=true   — upload + pin tarball, returns CID
  - POST /api/v0/cat?arg={cid}  — retrieve tarball by CID
  - POST /api/v0/pin/ls?arg={cid} — check if a CID is pinned

  A separate metadata store (local JSON sidecar) maps storage keys to CIDs,
  since IPFS is content-addressed and has no concept of named keys.

  Configuration via environment variables:
  - `OPSM_IPFS_API`      — Kubo API URL, default "http://localhost:5001"
  - `OPSM_IPFS_GATEWAY`  — Public gateway for retrieval URLs,
                           default "https://ipfs.io"
  - `OPSM_IPFS_PIN`      — "true"/"false", whether to pin on upload, default "true"
  """

  @behaviour Opsm.Storage.Backend

  @default_api "http://localhost:5001"
  @default_gateway "https://ipfs.io"
  @meta_path Path.expand("~/.cache/opsm/ipfs-index.json")
  @timeout_ms 60_000

  # ---------------------------------------------------------------------------
  # Backend callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def put(key, local_path, _opts) do
    api = api_url()
    pin? = System.get_env("OPSM_IPFS_PIN", "true") == "true"
    url = "#{api}/api/v0/add?pin=#{pin?}&cid-version=1"

    with {:ok, body} <- File.read(local_path) do
      boundary = "opsm-#{:rand.uniform(1_000_000)}"
      multipart_body = build_multipart(body, Path.basename(local_path), boundary)
      content_type = "multipart/form-data; boundary=#{boundary}"

      case Req.post(url,
             headers: [{"content-type", content_type}],
             body: multipart_body,
             receive_timeout: @timeout_ms
           ) do
        {:ok, %{status: 200, body: resp}} ->
          cid = extract_cid(resp)
          store_cid_mapping(key, cid)
          {:ok, key}

        {:ok, %{status: s, body: b}} ->
          {:error, "IPFS add returned #{s}: #{inspect(b)}"}

        {:error, reason} ->
          {:error, "IPFS add failed: #{inspect(reason)}"}
      end
    end
  end

  @impl true
  def get(key, dest_path, _opts) do
    case load_cid(key) do
      nil ->
        {:error, :not_found}

      cid ->
        api = api_url()
        url = "#{api}/api/v0/cat?arg=#{cid}"
        dest_path |> Path.dirname() |> File.mkdir_p!()

        case Req.post(url, into: File.stream!(dest_path), receive_timeout: @timeout_ms) do
          {:ok, %{status: 200}} -> {:ok, dest_path}
          {:ok, %{status: s}} -> {:error, "IPFS cat returned #{s}"}
          {:error, reason} -> {:error, "IPFS cat failed: #{inspect(reason)}"}
        end
    end
  end

  @impl true
  def exists?(key, _opts) do
    case load_cid(key) do
      nil ->
        false

      cid ->
        api = api_url()
        url = "#{api}/api/v0/pin/ls?arg=#{cid}&type=recursive"

        case Req.post(url, receive_timeout: 5_000) do
          {:ok, %{status: 200}} -> true
          _ -> false
        end
    end
  end

  @impl true
  def url(key, _opts) do
    case load_cid(key) do
      nil ->
        nil

      cid ->
        gateway = System.get_env("OPSM_IPFS_GATEWAY", @default_gateway)
        "#{gateway}/ipfs/#{cid}"
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp api_url, do: System.get_env("OPSM_IPFS_API", @default_api)

  defp extract_cid(resp) when is_map(resp), do: resp["Hash"] || resp["Cid"] || resp["cid"]

  defp extract_cid(resp) when is_binary(resp) do
    case Jason.decode(resp) do
      {:ok, map} -> extract_cid(map)
      _ -> nil
    end
  end

  defp extract_cid(_), do: nil

  # Build a minimal multipart/form-data body for /api/v0/add.
  defp build_multipart(file_data, filename, boundary) do
    [
      "--#{boundary}\r\n",
      "Content-Disposition: form-data; name=\"file\"; filename=\"#{filename}\"\r\n",
      "Content-Type: application/octet-stream\r\n",
      "\r\n",
      file_data,
      "\r\n",
      "--#{boundary}--\r\n"
    ]
    |> IO.iodata_to_binary()
  end

  # ---------------------------------------------------------------------------
  # CID index (key → CID map stored locally so we can look up content by key)
  # ---------------------------------------------------------------------------

  defp store_cid_mapping(key, cid) when is_binary(cid) do
    existing = load_index()
    updated = Map.put(existing, key, cid)
    File.write!(@meta_path, Jason.encode!(updated, pretty: false))
  end

  defp store_cid_mapping(_key, _cid), do: :ok

  defp load_cid(key) do
    load_index() |> Map.get(key)
  end

  defp load_index do
    case File.read(@meta_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, map} when is_map(map) -> map
          _ -> %{}
        end

      {:error, _} ->
        %{}
    end
  end
end
