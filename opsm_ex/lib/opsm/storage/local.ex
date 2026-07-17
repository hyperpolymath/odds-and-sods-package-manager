# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Storage.Local do
  @moduledoc """
  Local-disk storage backend — `~/.cache/opsm/packages/<key>`.

  This is the default backend and always present. S3/IPFS are overlaid on top.
  """

  @behaviour Opsm.Storage.Backend

  @cache_root Path.expand("~/.cache/opsm/packages")

  @impl true
  def put(key, local_path, _opts) do
    dest = Path.join(@cache_root, key)
    dest |> Path.dirname() |> File.mkdir_p!()

    case File.cp(local_path, dest) do
      :ok -> {:ok, key}
      {:error, reason} -> {:error, "Local put failed: #{reason}"}
    end
  end

  @impl true
  def get(key, dest_path, _opts) do
    src = Path.join(@cache_root, key)

    if File.exists?(src) do
      dest_path |> Path.dirname() |> File.mkdir_p!()

      case File.cp(src, dest_path) do
        :ok -> {:ok, dest_path}
        {:error, reason} -> {:error, "Local copy failed: #{reason}"}
      end
    else
      {:error, :not_found}
    end
  end

  @impl true
  def exists?(key, _opts), do: File.exists?(Path.join(@cache_root, key))

  @impl true
  def url(_key, _opts), do: nil

  @doc "Full path for a key in the local cache (used by Downloader directly)."
  def path_for(key), do: Path.join(@cache_root, key)

  @doc "Return cache root for health checks / clean operations."
  def cache_root, do: @cache_root
end
