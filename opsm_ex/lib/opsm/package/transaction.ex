# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Package.Transaction do
  @moduledoc """
  Transaction tracking for package installation.

  Tracks operations performed during install so they can be
  rolled back on failure. Provides atomic-ish install operations.

  Operations tracked:
  - Directories created
  - Files downloaded/created
  - Symlinks created
  - Database entries added
  """

  defstruct [
    :package_name,
    :started_at,
    directories: [],
    files: [],
    symlinks: [],
    db_entries: [],
    completed: false
  ]

  @type t :: %__MODULE__{
    package_name: String.t(),
    started_at: DateTime.t(),
    directories: [String.t()],
    files: [String.t()],
    symlinks: [String.t()],
    db_entries: [String.t()],
    completed: boolean()
  }

  @doc """
  Start a new transaction for package installation.
  """
  def new(package_name) do
    %__MODULE__{
      package_name: package_name,
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Record a directory creation.
  """
  def record_directory(txn, path) do
    %{txn | directories: [path | txn.directories]}
  end

  @doc """
  Record a file creation.
  """
  def record_file(txn, path) do
    %{txn | files: [path | txn.files]}
  end

  @doc """
  Record a symlink creation.
  """
  def record_symlink(txn, path) do
    %{txn | symlinks: [path | txn.symlinks]}
  end

  @doc """
  Record a database entry.
  """
  def record_db_entry(txn, package_name) do
    %{txn | db_entries: [package_name | txn.db_entries]}
  end

  @doc """
  Mark transaction as completed successfully.
  """
  def complete(txn) do
    %{txn | completed: true}
  end

  @doc """
  Roll back all operations in the transaction.
  Called on install failure to clean up partial state.
  Does nothing if transaction was already completed successfully.
  """
  def rollback(txn) do
    if txn.completed do
      IO.puts("  Transaction completed - skipping rollback")
      :ok
    else
      do_rollback(txn)
    end
  end

  defp do_rollback(txn) do
    IO.puts("  Rolling back installation...")

    errors = []

    # Remove symlinks first (safest, no dependencies)
    errors = errors ++ remove_symlinks(txn.symlinks)

    # Remove files
    errors = errors ++ remove_files(txn.files)

    # Remove directories (in reverse order - deepest first)
    errors = errors ++ remove_directories(Enum.reverse(txn.directories))

    # Note: We don't remove db_entries here since we typically
    # don't add them until after successful install

    if errors == [] do
      IO.puts("  ✓ Rollback complete")
      :ok
    else
      IO.puts("  ⚠ Rollback completed with #{length(errors)} warning(s)")
      {:ok, errors}
    end
  end

  # Moved rollback logic to private function

  @doc """
  Create a directory and record it in the transaction.
  Returns updated transaction or error.
  """
  def mkdir_p(txn, path) do
    case File.mkdir_p(path) do
      :ok ->
        {:ok, record_directory(txn, path)}
      {:error, reason} ->
        {:error, "Failed to create directory #{path}: #{reason}"}
    end
  end

  @doc """
  Create a symlink safely and record it in the transaction.
  Includes security checks for symlink attacks.
  """
  def safe_symlink(txn, source, target) do
    # Security check: ensure target doesn't already exist as something unexpected
    case File.lstat(target) do
      {:ok, %{type: :symlink}} ->
        # Existing symlink - check if it points to our source
        case File.read_link(target) do
          {:ok, ^source} ->
            # Already points to correct location, just record it
            {:ok, record_symlink(txn, target)}
          {:ok, other} ->
            {:error, "Target #{target} is a symlink to #{other}, not #{source}"}
          {:error, reason} ->
            {:error, "Cannot read symlink #{target}: #{reason}"}
        end

      {:ok, %{type: type}} ->
        # Exists as something else (file, directory)
        {:error, "Target #{target} already exists as #{type}"}

      {:error, :enoent} ->
        # Doesn't exist - safe to create
        case File.ln_s(source, target) do
          :ok ->
            {:ok, record_symlink(txn, target)}
          {:error, reason} ->
            {:error, "Failed to create symlink #{target}: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Cannot check target #{target}: #{reason}"}
    end
  end

  @doc """
  Move a file atomically (rename) and record in transaction.
  Used for temp file -> final location pattern.
  """
  def atomic_move(txn, source, dest) do
    case File.rename(source, dest) do
      :ok ->
        {:ok, record_file(txn, dest)}
      {:error, :exdev} ->
        # Cross-device move - need to copy and delete
        case File.cp(source, dest) do
          :ok ->
            File.rm(source)
            {:ok, record_file(txn, dest)}
          {:error, reason} ->
            {:error, "Failed to copy #{source} to #{dest}: #{reason}"}
        end
      {:error, reason} ->
        {:error, "Failed to move #{source} to #{dest}: #{reason}"}
    end
  end

  # Private helpers

  defp remove_symlinks(symlinks) do
    Enum.flat_map(symlinks, fn path ->
      case File.rm(path) do
        :ok ->
          IO.puts("    ✓ Removed symlink: #{Path.basename(path)}")
          []
        {:error, :enoent} ->
          # Already gone
          []
        {:error, reason} ->
          IO.puts("    ⚠ Failed to remove symlink #{path}: #{reason}")
          [{path, reason}]
      end
    end)
  end

  defp remove_files(files) do
    Enum.flat_map(files, fn path ->
      case File.rm(path) do
        :ok ->
          IO.puts("    ✓ Removed file: #{Path.basename(path)}")
          []
        {:error, :enoent} ->
          []
        {:error, reason} ->
          IO.puts("    ⚠ Failed to remove file #{path}: #{reason}")
          [{path, reason}]
      end
    end)
  end

  defp remove_directories(dirs) do
    Enum.flat_map(dirs, fn path ->
      # Only remove if empty (we created it, so if it's not empty, something else used it)
      case File.rmdir(path) do
        :ok ->
          IO.puts("    ✓ Removed directory: #{path}")
          []
        {:error, :enoent} ->
          []
        {:error, :enotempty} ->
          # Directory not empty - that's fine, leave it
          []
        {:error, :eexist} ->
          # Same as enotempty on some systems
          []
        {:error, reason} ->
          IO.puts("    ⚠ Failed to remove directory #{path}: #{reason}")
          [{path, reason}]
      end
    end)
  end
end
