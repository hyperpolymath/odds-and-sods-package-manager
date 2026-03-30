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

  @doc false
  @metadata_cache_dir Path.expand("~/.cache/opsm/metadata")

  defp clean_metadata(dry_run) do
    # Registry metadata cache: cached API responses, version lists, and
    # package metadata from registry adapters (npm, hex, crates, pypi, etc.)
    # Also cleans the ETS-backed RegistryCache entries by clearing the
    # on-disk metadata directory.
    clean_directory(@metadata_cache_dir, "registry metadata cache", dry_run)
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
    alias Opsm.Package.Installer

    case load_history() do
      [] ->
        {:error, "No history to undo"}

      [last | _rest] ->
        case last["operation"] do
          "install" ->
            package = last["details"]["package"]
            IO.puts("Undoing: install #{package}")
            case Installer.remove(package) do
              :ok ->
                record_history("undo_install", %{"package" => package, "undone_id" => last["id"]})
                IO.puts("✓ Removed #{package}")
                {:ok, :removed, package}
              {:error, reason} ->
                IO.puts("✗ Failed to undo install: #{reason}")
                {:error, reason}
            end

          "remove" ->
            package = last["details"]["package"]
            forth_str = last["details"]["forth"] || "generic"
            version = last["details"]["version"]
            forth = Opsm.Validation.safe_to_forth(forth_str)

            IO.puts("Undoing: remove #{package}")
            case Installer.install(forth, package, version: version || "latest") do
              {:ok, _} ->
                record_history("undo_remove", %{"package" => package, "undone_id" => last["id"]})
                IO.puts("✓ Reinstalled #{package}")
                {:ok, :reinstalled, package}
              {:error, reason} ->
                IO.puts("✗ Failed to undo remove: #{inspect(reason)}")
                {:error, reason}
            end

          op ->
            {:error, "Cannot undo operation: #{op}"}
        end
    end
  end

  @doc """
  Redo the last undone operation (reverse the most recent undo).
  """
  def redo_last do
    alias Opsm.Package.Installer

    case load_history() do
      [] ->
        {:error, "No history to redo"}

      [last | _rest] ->
        case last["operation"] do
          "undo_install" ->
            # The undo removed a package — redo means reinstall it
            package = last["details"]["package"]
            # Look back in history for the original install to get forth/version
            original = find_history_entry_for(package, "install")
            forth_str = (original && original["details"]["forth"]) || "generic"
            version = (original && original["details"]["version"]) || "latest"
            forth = Opsm.Validation.safe_to_forth(forth_str)

            IO.puts("Redoing: install #{package}")
            case Installer.install(forth, package, version: version) do
              {:ok, _} ->
                record_history("redo_install", %{"package" => package, "redone_id" => last["id"]})
                IO.puts("✓ Reinstalled #{package}")
                {:ok, :reinstalled, package}
              {:error, reason} ->
                IO.puts("✗ Failed to redo: #{inspect(reason)}")
                {:error, reason}
            end

          "undo_remove" ->
            # The undo reinstalled a package — redo means remove it again
            package = last["details"]["package"]
            IO.puts("Redoing: remove #{package}")
            case Installer.remove(package) do
              :ok ->
                record_history("redo_remove", %{"package" => package, "redone_id" => last["id"]})
                IO.puts("✓ Removed #{package}")
                {:ok, :removed, package}
              {:error, reason} ->
                IO.puts("✗ Failed to redo: #{inspect(reason)}")
                {:error, reason}
            end

          op ->
            {:error, "Last operation '#{op}' is not an undo — nothing to redo"}
        end
    end
  end

  defp find_history_entry_for(package, operation) do
    load_history()
    |> Enum.find(fn entry ->
      entry["operation"] == operation and
        entry["details"]["package"] == package
    end)
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
    dry_run = Keyword.get(opts, :dry_run, false)
    db_path = Path.expand("~/.local/share/opsm/installed.json")
    lockfile_path = Path.expand("~/.local/share/opsm/lockfile.json")

    IO.puts("Checking for unused dependencies...")

    # Load installed packages
    installed = case File.read(db_path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, pkgs} when is_map(pkgs) -> pkgs
          _ -> %{}
        end
      {:error, _} -> %{}
    end

    # Load lockfile to determine dependency graph
    lockfile_deps = case File.read(lockfile_path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, lock} when is_map(lock) ->
            lock["packages"] || []
          _ -> []
        end
      {:error, _} -> []
    end

    # Build set of packages that are dependencies of other packages
    all_dep_names = lockfile_deps
      |> Enum.flat_map(fn pkg ->
        (pkg["dependencies"] || [])
      end)
      |> MapSet.new()

    # Find packages that were installed as dependencies (not explicitly)
    # and are no longer required by any other package
    orphans = installed
      |> Enum.filter(fn {_name, info} ->
        info["auto_installed"] == true
      end)
      |> Enum.reject(fn {name, _info} ->
        MapSet.member?(all_dep_names, name)
      end)
      |> Enum.map(fn {name, info} -> {name, info["version"] || "unknown"} end)

    if orphans == [] do
      IO.puts("")
      IO.puts("No unused dependencies found")
      {:ok, []}
    else
      IO.puts("")
      IO.puts("Found #{length(orphans)} unused dependencies:")
      for {name, version} <- orphans do
        IO.puts("  #{name}@#{version}")
      end
      IO.puts("")

      if dry_run do
        IO.puts("[DRY RUN] Would remove #{length(orphans)} packages")
        {:ok, orphans}
      else
        # Remove each orphan
        removed = Enum.map(orphans, fn {name, _version} ->
          updated = Map.delete(installed, name)
          db_path |> Path.dirname() |> File.mkdir_p!()
          File.write!(db_path, Jason.encode!(updated, pretty: true))

          # Record in history
          record_history("autoremove", %{"package" => name})
          name
        end)

        IO.puts("Removed #{length(removed)} unused dependencies")
        {:ok, removed}
      end
    end
  end

  # ============================================
  # Upgrade Path Calculation
  # ============================================

  @doc """
  Calculate the upgrade path for a package from its current version to the
  latest available version in its registry.

  Returns `{:ok, upgrade_info}` with a map containing:
  - `:current` - the currently installed version
  - `:latest` - the latest available version
  - `:available` - list of versions between current and latest
  - `:pinned` - whether the package is pinned
  - `:action` - `:up_to_date`, `:upgrade_available`, or `:pinned_skip`

  Returns `{:error, reason}` if the package is not installed or the
  registry is unreachable.
  """
  def upgrade_path(package_name, opts \\ []) do
    db_path = Keyword.get(opts, :db_path, Path.expand("~/.local/share/opsm/installed.json"))

    installed = case File.read(db_path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, pkgs} when is_map(pkgs) -> pkgs
          _ -> %{}
        end
      {:error, _} -> %{}
    end

    case Map.get(installed, package_name) do
      nil ->
        {:error, :not_installed}

      info ->
        current_version = info["version"] || "0.0.0"
        forth_str = info["forth"] || "npm"
        forth = Opsm.Validation.safe_to_forth(forth_str)

        is_pinned = pinned?(package_name)
        pin_info = get_pin(package_name)
        pinned_version = if pin_info, do: pin_info["version"], else: nil

        case Opsm.Registries.Registry.versions(forth, package_name) do
          {:ok, all_versions} ->
            # Filter to versions newer than current
            newer = Enum.filter(all_versions, fn v ->
              version_newer?(v, current_version)
            end)

            latest = List.first(newer) || current_version

            action = cond do
              is_pinned and pinned_version != nil ->
                :pinned_skip

              newer == [] ->
                :up_to_date

              true ->
                :upgrade_available
            end

            {:ok, %{
              package: package_name,
              forth: forth,
              current: current_version,
              latest: latest,
              available: newer,
              pinned: is_pinned,
              pinned_version: pinned_version,
              action: action
            }}

          {:error, reason} ->
            {:error, {:registry_error, reason}}
        end
    end
  end

  defp version_newer?(candidate, current) do
    case {parse_semver(candidate), parse_semver(current)} do
      {{:ok, cand}, {:ok, curr}} ->
        Version.compare(cand, curr) == :gt

      _ ->
        candidate > current
    end
  end

  defp parse_semver(v) do
    v
    |> String.replace(~r/^v/, "")
    |> String.split("-")
    |> List.first()
    |> Version.parse()
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
