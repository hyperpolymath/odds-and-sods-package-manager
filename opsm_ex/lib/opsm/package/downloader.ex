# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Package.Downloader do
  @moduledoc """
  Package download and verification.
  Downloads packages from registries and verifies checksums.

  Security features:
  - Downloads to temp file first, moves on success (atomic)
  - Warns when checksum is missing
  - Verifies checksum before accepting download
  """

  @cache_dir Path.expand("~/.cache/opsm/packages")
  @temp_dir Path.expand("~/.cache/opsm/tmp")

  @doc """
  Download a package to the cache directory.
  Returns path to downloaded file.
  """
  def download(package, opts \\ []) do
    url = package.tarball_url
    checksum = package.checksum
    algo = package.checksum_algo || :sha256

    if is_nil(url) do
      {:error, "No tarball URL available for #{package.package}"}
    else
      cache_path = cache_path_for(package)

      # Check if already cached
      if File.exists?(cache_path) and not Keyword.get(opts, :force, false) do
        case verify_checksum(cache_path, checksum, algo) do
          :ok -> {:ok, cache_path}
          {:error, _} ->
            # Checksum mismatch, re-download
            do_download(url, cache_path, checksum, algo)
        end
      else
        do_download(url, cache_path, checksum, algo)
      end
    end
  end

  @doc """
  Download a package to a specific location.
  """
  def download_to(package, dest_path, opts \\ []) do
    url = package.tarball_url
    checksum = package.checksum
    algo = package.checksum_algo || :sha256

    if is_nil(url) do
      {:error, "No tarball URL available for #{package.package}"}
    else
      do_download(url, dest_path, checksum, algo, opts)
    end
  end

  @doc """
  Get the cache path for a package.
  """
  def cache_path_for(package) do
    forth = package.forth
    name = package.package
    version = package.version
    ext = extension_for(forth)

    ensure_cache_dir()
    Path.join([@cache_dir, to_string(forth), "#{name}-#{version}#{ext}"])
  end

  @doc """
  Clear cached packages for a specific forth or all forths.
  """
  def clear_cache(forth \\ :all) do
    case forth do
      :all ->
        case File.rm_rf(@cache_dir) do
          {:ok, _} -> :ok
          {:error, reason, path} -> {:error, "Failed to clear cache at #{path}: #{reason}"}
        end

      forth ->
        path = Path.join(@cache_dir, to_string(forth))
        case File.rm_rf(path) do
          {:ok, _} -> :ok
          {:error, reason, p} -> {:error, "Failed to clear cache at #{p}: #{reason}"}
        end
    end
  end

  @doc """
  List cached packages.
  """
  def list_cache(forth \\ :all) do
    ensure_cache_dir()

    case forth do
      :all ->
        case File.ls(@cache_dir) do
          {:ok, dirs} ->
            Enum.flat_map(dirs, fn dir ->
              list_cache_dir(Path.join(@cache_dir, dir), dir)
            end)

          {:error, _} -> []
        end

      forth ->
        dir = Path.join(@cache_dir, to_string(forth))
        list_cache_dir(dir, to_string(forth))
    end
  end

  # Internal functions

  defp do_download(url, dest_path, checksum, algo, opts \\ []) do
    # Ensure directories exist
    dest_path |> Path.dirname() |> File.mkdir_p!()
    File.mkdir_p!(@temp_dir)

    # Download to temp file first (D3: atomic download)
    temp_path = Path.join(@temp_dir, "download_#{:rand.uniform(1_000_000)}_#{System.system_time(:millisecond)}")

    IO.puts("  Downloading: #{url}")

    # Warn if no checksum provided (F3)
    if is_nil(checksum) do
      IO.puts("  ⚠ Warning: No checksum provided - cannot verify download integrity")
    end

    result = case Req.get(url, into: File.stream!(temp_path), receive_timeout: 60_000) do
      {:ok, %{status: 200}} ->
        case verify_checksum(temp_path, checksum, algo) do
          :ok ->
            # Atomic move from temp to final destination
            case File.rename(temp_path, dest_path) do
              :ok ->
                size = File.stat!(dest_path).size
                IO.puts("  Downloaded: #{format_size(size)}")
                {:ok, dest_path}

              {:error, :exdev} ->
                # Cross-device - copy and delete
                case File.cp(temp_path, dest_path) do
                  :ok ->
                    File.rm(temp_path)
                    size = File.stat!(dest_path).size
                    IO.puts("  Downloaded: #{format_size(size)}")
                    {:ok, dest_path}
                  {:error, reason} ->
                    {:error, "Failed to copy downloaded file: #{reason}"}
                end

              {:error, reason} ->
                {:error, "Failed to move downloaded file: #{reason}"}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:ok, %{status: 302, headers: headers}} ->
        # Follow redirect - clean up temp file first
        File.rm(temp_path)
        case List.keyfind(headers, "location", 0) do
          {"location", redirect_url} ->
            do_download(redirect_url, dest_path, checksum, algo, opts)
          _ ->
            {:error, "Redirect without location header"}
        end

      {:ok, %{status: status}} ->
        {:error, "Download failed with status #{status}"}

      {:error, reason} ->
        {:error, "Download failed: #{inspect(reason)}"}
    end

    # Clean up temp file on any error
    case result do
      {:ok, _} -> result
      {:error, _} ->
        File.rm(temp_path)
        result
    end
  end

  defp verify_checksum(_path, nil, _algo), do: :ok

  defp verify_checksum(path, expected, algo) do
    actual = compute_checksum(path, algo)

    if String.downcase(actual) == String.downcase(expected) do
      :ok
    else
      {:error, "Checksum mismatch: expected #{expected}, got #{actual}"}
    end
  end

  defp compute_checksum(path, algo) do
    hash_algo = case algo do
      :sha256 -> :sha256
      :sha1 -> :sha
      :md5 -> :md5
      _ -> :sha256
    end

    File.stream!(path, [], 65536)
    |> Enum.reduce(:crypto.hash_init(hash_algo), fn chunk, acc ->
      :crypto.hash_update(acc, chunk)
    end)
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp extension_for(:npm), do: ".tgz"
  defp extension_for(:cargo), do: ".crate"
  defp extension_for(:hex), do: ".tar"
  defp extension_for(:pypi), do: ".tar.gz"
  defp extension_for(:gem), do: ".gem"
  defp extension_for(_), do: ".tar.gz"

  defp ensure_cache_dir do
    File.mkdir_p!(@cache_dir)
  end

  defp list_cache_dir(dir, forth_name) do
    case File.ls(dir) do
      {:ok, files} ->
        Enum.map(files, fn file ->
          path = Path.join(dir, file)
          stat = File.stat!(path)
          %{
            forth: forth_name,
            file: file,
            path: path,
            size: stat.size,
            mtime: stat.mtime
          }
        end)

      {:error, _} -> []
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
end
