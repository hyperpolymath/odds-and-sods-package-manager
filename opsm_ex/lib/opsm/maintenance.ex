# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Maintenance do
  @moduledoc """
  Package maintenance operations.

  Provides:
  - Cache cleaning
  - History tracking and undo/redo
  - Pin/unpin (version locking)
  - Autoremove unused dependencies
  """


  @history_path Path.expand("~/.local/share/opsm/history.json")
  @pins_path Path.expand("~/.local/share/opsm/pins.json")
  @max_history_entries 100

  # ============================================
  # Clean operations
  # ============================================

  @doc """
  Clean cached data.
  Supports: all, cache, metadata, packages, tmp
  """
  def clean(what, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    case what do
      "all" ->
        clean_all(dry_run)

      "cache" ->
        clean_cache(dry_run)

      "metadata" ->
        clean_metadata(dry_run)

      "packages" ->
        # This would remove downloaded packages, not installed ones
        clean_cache(dry_run)

      "tmp" ->
        clean_tmp(dry_run)

      _ ->
        {:error, "Unknown clean target: #{what}. Use: all, cache, metadata, tmp"}
    end
  end

  defp clean_all(dry_run) do
    IO.puts("Cleaning all cached data...")

    with {:ok, cache_size} <- clean_cache(dry_run),
         {:ok, meta_size} <- clean_metadata(dry_run),
         {:ok, tmp_size} <- clean_tmp(dry_run) do
      total = cache_size + meta_size + tmp_size
      IO.puts("")
      IO.puts("✓ Freed #{format_size(total)}")
      {:ok, total}
    end
  end

  defp clean_cache(dry_run) do
    cache_dir = Path.expand("~/.cache/opsm/packages")
    clean_directory(cache_dir, "package cache", dry_run)
  end

  defp clean_metadata(_dry_run) do
    # Registry metadata cache would go here
    # For now, this is a placeholder
    IO.puts("  No metadata cache to clean")
    {:ok, 0}
  end

  defp clean_tmp(dry_run) do
    tmp_dir = Path.expand("~/.cache/opsm/tmp")
    clean_directory(tmp_dir, "temporary files", dry_run)
  end

  defp clean_directory(path, label, dry_run) do
    if File.exists?(path) do
      size = dir_size(path)

      if dry_run do
        IO.puts("  [DRY RUN] Would remove #{label}: #{format_size(size)}")
        {:ok, 0}
      else
        case File.rm_rf(path) do
          {:ok, _} ->
            IO.puts("  ✓ Removed #{label}: #{format_size(size)}")
            {:ok, size}
          {:error, reason, p} ->
            IO.puts("  ✗ Failed to remove #{p}: #{reason}")
            {:error, reason}
        end
      end
    else
      IO.puts("  No #{label} to clean")
      {:ok, 0}
    end
  end

  defp dir_size(path) do
    case File.ls(path) do
      {:ok, files} ->
        Enum.reduce(files, 0, fn file, acc ->
          full_path = Path.join(path, file)
          case File.stat(full_path) do
            {:ok, %{type: :directory}} -> acc + dir_size(full_path)
            {:ok, %{size: size}} -> acc + size
            _ -> acc
          end
        end)
      _ -> 0
    end
  end

  # ============================================
  # History operations
  # ============================================

  @doc """
  Record an operation in history.
  """
  def record_history(operation, details) do
    entry = %{
      "id" => generate_id(),
      "operation" => operation,
      "details" => details,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    history = load_history()
    updated = [entry | history] |> Enum.take(@max_history_entries)
    save_history(updated)

    entry["id"]
  end

  @doc """
  List recent history entries.
  """
  def list_history(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    history = load_history()
    Enum.take(history, limit)
  end

  @doc """
  Get a specific history entry by ID.
  """
  def get_history_entry(id) do
    history = load_history()
    Enum.find(history, fn entry -> entry["id"] == id end)
  end

  @doc """
  Undo the last operation (if possible).
  """
  def undo_last do
    case load_history() do
      [] ->
        {:error, "No history to undo"}

      [last | _rest] ->
        case last["operation"] do
          "install" ->
            package = last["details"]["package"]
            IO.puts("Undoing: install #{package}")
            IO.puts("⊘ Undo install not yet implemented")
            {:ok, :would_remove, package}

          "remove" ->
            package = last["details"]["package"]
            IO.puts("Undoing: remove #{package}")
            IO.puts("⊘ Undo remove not yet implemented")
            {:ok, :would_reinstall, package}

          op ->
            {:error, "Cannot undo operation: #{op}"}
        end
    end
  end

  defp load_history do
    case File.read(@history_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end
      _ -> []
    end
  end

  defp save_history(history) do
    @history_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(@history_path, Jason.encode!(history, pretty: true))
  end

  # ============================================
  # Pin/Unpin operations
  # ============================================

  @doc """
  Pin a package to a specific version.
  Prevents updates beyond this version.
  """
  def pin(package_name, version \\ nil) do
    pins = load_pins()

    pin_entry = %{
      "package" => package_name,
      "version" => version,
      "pinned_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    # Remove existing pin for this package
    pins = Enum.reject(pins, fn p -> p["package"] == package_name end)
    updated = [pin_entry | pins]
    save_pins(updated)

    if version do
      IO.puts("✓ Pinned #{package_name} to version #{version}")
    else
      IO.puts("✓ Pinned #{package_name} to current version")
    end

    :ok
  end

  @doc """
  Unpin a package (allow updates again).
  """
  def unpin(package_name) do
    pins = load_pins()

    if Enum.any?(pins, fn p -> p["package"] == package_name end) do
      updated = Enum.reject(pins, fn p -> p["package"] == package_name end)
      save_pins(updated)
      IO.puts("✓ Unpinned #{package_name}")
      :ok
    else
      {:error, "Package #{package_name} is not pinned"}
    end
  end

  @doc """
  List all pinned packages.
  """
  def list_pins do
    load_pins()
  end

  @doc """
  Check if a package is pinned.
  """
  def pinned?(package_name) do
    pins = load_pins()
    Enum.any?(pins, fn p -> p["package"] == package_name end)
  end

  @doc """
  Get pin info for a package.
  """
  def get_pin(package_name) do
    pins = load_pins()
    Enum.find(pins, fn p -> p["package"] == package_name end)
  end

  defp load_pins do
    case File.read(@pins_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end
      _ -> []
    end
  end

  defp save_pins(pins) do
    @pins_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(@pins_path, Jason.encode!(pins, pretty: true))
  end

  # ============================================
  # Autoremove
  # ============================================

  @doc """
  Remove packages that are no longer needed.
  (Dependencies of removed packages)
  """
  def autoremove(opts \\ []) do
    _dry_run = Keyword.get(opts, :dry_run, false)

    # This would require dependency tracking
    # For now, just report that there's nothing to remove
    IO.puts("Checking for unused dependencies...")
    IO.puts("")
    IO.puts("No unused dependencies found")
    IO.puts("")
    IO.puts("Note: Autoremove requires dependency tracking which is not yet implemented")

    {:ok, []}
  end

  # ============================================
  # Helpers
  # ============================================

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 2)} MB"
end
