# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Storage.Manager do
  @moduledoc """
  Multi-backend tarball cache coordinator.

  Read order: Local → S3 → IPFS
  Write order: all configured backends (write-through)

  "Configured" means:
  - Local: always active
  - S3:    active when OPSM_S3_BUCKET + AWS credentials are set
  - IPFS:  active when OPSM_IPFS_API is set (or falls back to localhost:5001
           if a Kubo node is running there)

  The local backend is always the final read destination: after a cache hit
  in S3 or IPFS, the tarball is saved locally before the path is returned.
  This means callers always receive a local filesystem path.
  """

  require Logger

  alias Opsm.Storage.{Local, S3, Ipfs}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Fetch a tarball to `local_path`.

  Checks Local first, then S3, then IPFS. If found in a remote backend,
  stores locally before returning. Returns `{:ok, local_path}` or
  `{:error, :not_found}` (caller is expected to download from origin).
  """
  @spec fetch(String.t(), Path.t()) :: {:ok, Path.t()} | {:error, :not_found}
  def fetch(key, local_path) do
    if Local.exists?(key, []) do
      {:ok, Local.path_for(key)}
    else
      case try_remote_fetch(key, local_path) do
        {:ok, _path} = ok ->
          # Populate local cache from the fetched file for future hits.
          Local.put(key, local_path, [])
          ok

        {:error, _} ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Store a tarball in all configured backends after a fresh download.

  Failures in S3/IPFS are logged as warnings and never propagate.
  """
  @spec store(String.t(), Path.t()) :: :ok
  def store(key, local_path) do
    # Local is the primary — it should already be there (Downloader wrote it).
    # Push to remote backends silently.
    if s3_configured?() do
      case S3.put(key, local_path, []) do
        {:ok, _}     -> Logger.debug("Stored #{key} in S3")
        {:error, reason} -> Logger.warning("S3 store failed for #{key}: #{inspect(reason)}")
      end
    end

    if ipfs_active?() do
      case Ipfs.put(key, local_path, []) do
        {:ok, _}     -> Logger.debug("Stored #{key} in IPFS")
        {:error, reason} -> Logger.warning("IPFS store failed for #{key}: #{inspect(reason)}")
      end
    end

    :ok
  end

  @doc """
  Return the public URL for a key from the first backend that has one, or nil.
  """
  @spec public_url(String.t()) :: String.t() | nil
  def public_url(key) do
    cond do
      s3_configured?()  -> S3.url(key, [])
      ipfs_active?()    -> Ipfs.url(key, [])
      true              -> nil
    end
  end

  @doc """
  Return a map of backend → status for health checks / `opsm status`.
  """
  @spec status() :: map()
  def status do
    %{
      local: %{active: true, path: Local.cache_root()},
      s3:    %{active: s3_configured?(), bucket: System.get_env("OPSM_S3_BUCKET")},
      ipfs:  %{active: ipfs_active?(), api: System.get_env("OPSM_IPFS_API", "not set")}
    }
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp try_remote_fetch(key, dest_path) do
    cond do
      s3_configured?() ->
        case S3.get(key, dest_path, []) do
          {:ok, _} = ok -> ok
          {:error, :not_found} -> try_ipfs_fetch(key, dest_path)
          {:error, reason} ->
            Logger.debug("S3 fetch miss for #{key}: #{inspect(reason)}")
            try_ipfs_fetch(key, dest_path)
        end

      ipfs_active?() -> try_ipfs_fetch(key, dest_path)

      true -> {:error, :not_found}
    end
  end

  defp try_ipfs_fetch(key, dest_path) do
    if ipfs_active?() do
      case Ipfs.get(key, dest_path, []) do
        {:ok, _} = ok -> ok
        {:error, reason} ->
          Logger.debug("IPFS fetch miss for #{key}: #{inspect(reason)}")
          {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  defp s3_configured? do
    System.get_env("OPSM_S3_BUCKET") != nil and
      System.get_env("AWS_ACCESS_KEY_ID") != nil and
      System.get_env("AWS_SECRET_ACCESS_KEY") != nil
  end

  defp ipfs_active? do
    # Active if explicitly configured, OR if a local Kubo node is set.
    System.get_env("OPSM_IPFS_API") != nil
  end
end
