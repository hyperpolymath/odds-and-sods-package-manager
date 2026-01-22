# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Lockfile do
  @moduledoc """
  Lock file management for reproducible package installations.

  The lock file (opm.lock) records:
  - Exact versions of all installed packages
  - Checksums for integrity verification
  - Dependency tree structure
  - Installation timestamps

  This enables:
  - Reproducible installs across machines
  - Faster installs (skip resolution, use cached versions)
  - Dependency auditing
  """

  @lockfile_name "opm.lock"
  @lockfile_version "1"

  @type package_entry :: %{
    name: String.t(),
    version: String.t(),
    forth: atom(),
    checksum: String.t() | nil,
    checksum_algo: String.t() | nil,
    source_url: String.t() | nil,
    dependencies: [String.t()],
    installed_at: String.t()
  }

  @type lockfile :: %{
    version: String.t(),
    generated_at: String.t(),
    packages: %{String.t() => package_entry()}
  }

  @doc """
  Read the lock file from the current directory or specified path.
  Returns {:ok, lockfile} or {:error, reason}.
  """
  def read(path \\ @lockfile_name) do
    case File.read(path) do
      {:ok, content} ->
        parse_lockfile(content)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, "Failed to read lock file: #{reason}"}
    end
  end

  @doc """
  Write a lock file to the current directory or specified path.
  """
  def write(lockfile, path \\ @lockfile_name) do
    content = serialize_lockfile(lockfile)

    case File.write(path, content) do
      :ok ->
        {:ok, path}

      {:error, reason} ->
        {:error, "Failed to write lock file: #{reason}"}
    end
  end

  @doc """
  Create a new empty lockfile structure.
  """
  def new do
    %{
      version: @lockfile_version,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      packages: %{}
    }
  end

  @doc """
  Add or update a package entry in the lockfile.
  """
  def add_package(lockfile, package_info) do
    entry = %{
      name: package_info.name,
      version: package_info.version,
      forth: package_info.forth,
      checksum: Map.get(package_info, :checksum),
      checksum_algo: Map.get(package_info, :checksum_algo, "sha256"),
      source_url: Map.get(package_info, :source_url),
      dependencies: Map.get(package_info, :dependencies, []),
      installed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    key = "#{package_info.name}@#{package_info.forth}"
    packages = Map.put(lockfile.packages, key, entry)

    %{lockfile |
      packages: packages,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Remove a package from the lockfile.
  """
  def remove_package(lockfile, name, forth) do
    key = "#{name}@#{forth}"
    packages = Map.delete(lockfile.packages, key)

    %{lockfile |
      packages: packages,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Get a package entry from the lockfile.
  """
  def get_package(lockfile, name, forth) do
    key = "#{name}@#{forth}"
    Map.get(lockfile.packages, key)
  end

  @doc """
  Check if a package exists in the lockfile.
  """
  def has_package?(lockfile, name, forth) do
    key = "#{name}@#{forth}"
    Map.has_key?(lockfile.packages, key)
  end

  @doc """
  List all packages in the lockfile.
  """
  def list_packages(lockfile) do
    lockfile.packages
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Get packages for a specific forth/ecosystem.
  """
  def packages_for_forth(lockfile, forth) do
    lockfile.packages
    |> Map.values()
    |> Enum.filter(fn p -> p.forth == forth end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Verify package integrity against lockfile.
  Returns :ok if matches, {:mismatch, details} if different.
  """
  def verify_package(lockfile, name, forth, actual_checksum) do
    case get_package(lockfile, name, forth) do
      nil ->
        {:error, :not_in_lockfile}

      %{checksum: nil} ->
        {:ok, :no_checksum_recorded}

      %{checksum: expected} when expected == actual_checksum ->
        :ok

      %{checksum: expected} ->
        {:mismatch, %{expected: expected, actual: actual_checksum}}
    end
  end

  @doc """
  Check if the lockfile is out of sync with installed packages.
  Returns list of differences.
  """
  def check_sync(lockfile, installed_packages) do
    locked_set = lockfile.packages
    |> Map.keys()
    |> MapSet.new()

    installed_set = installed_packages
    |> Enum.map(fn p -> "#{p.name}@#{p.forth}" end)
    |> MapSet.new()

    missing_from_lock = MapSet.difference(installed_set, locked_set)
    missing_from_install = MapSet.difference(locked_set, installed_set)

    %{
      in_sync: MapSet.size(missing_from_lock) == 0 and MapSet.size(missing_from_install) == 0,
      missing_from_lockfile: MapSet.to_list(missing_from_lock),
      not_installed: MapSet.to_list(missing_from_install)
    }
  end

  @doc """
  Find the lockfile by searching up the directory tree.
  Returns {:ok, path} or {:error, :not_found}.
  """
  def find_lockfile(start_dir \\ File.cwd!()) do
    do_find_lockfile(start_dir)
  end

  # Private functions

  defp do_find_lockfile("/"), do: {:error, :not_found}

  defp do_find_lockfile(dir) do
    path = Path.join(dir, @lockfile_name)

    if File.exists?(path) do
      {:ok, path}
    else
      parent = Path.dirname(dir)
      if parent == dir do
        {:error, :not_found}
      else
        do_find_lockfile(parent)
      end
    end
  end

  defp parse_lockfile(content) do
    case Jason.decode(content) do
      {:ok, data} ->
        lockfile = %{
          version: Map.get(data, "version", "1"),
          generated_at: Map.get(data, "generated_at", ""),
          packages: parse_packages(Map.get(data, "packages", %{}))
        }
        {:ok, lockfile}

      {:error, reason} ->
        {:error, "Invalid lock file format: #{inspect(reason)}"}
    end
  end

  defp parse_packages(packages_map) when is_map(packages_map) do
    packages_map
    |> Enum.map(fn {key, value} ->
      entry = %{
        name: Map.get(value, "name", ""),
        version: Map.get(value, "version", ""),
        forth: String.to_existing_atom(Map.get(value, "forth", "unknown")),
        checksum: Map.get(value, "checksum"),
        checksum_algo: Map.get(value, "checksum_algo"),
        source_url: Map.get(value, "source_url"),
        dependencies: Map.get(value, "dependencies", []),
        installed_at: Map.get(value, "installed_at", "")
      }
      {key, entry}
    end)
    |> Map.new()
  rescue
    ArgumentError ->
      # String.to_existing_atom failed - use string
      packages_map
      |> Enum.map(fn {key, value} ->
        entry = %{
          name: Map.get(value, "name", ""),
          version: Map.get(value, "version", ""),
          forth: String.to_atom(Map.get(value, "forth", "unknown")),
          checksum: Map.get(value, "checksum"),
          checksum_algo: Map.get(value, "checksum_algo"),
          source_url: Map.get(value, "source_url"),
          dependencies: Map.get(value, "dependencies", []),
          installed_at: Map.get(value, "installed_at", "")
        }
        {key, entry}
      end)
      |> Map.new()
  end

  defp serialize_lockfile(lockfile) do
    data = %{
      "version" => lockfile.version,
      "generated_at" => lockfile.generated_at,
      "packages" => serialize_packages(lockfile.packages)
    }

    Jason.encode!(data, pretty: true)
  end

  defp serialize_packages(packages) do
    packages
    |> Enum.map(fn {key, entry} ->
      value = %{
        "name" => entry.name,
        "version" => entry.version,
        "forth" => to_string(entry.forth),
        "checksum" => entry.checksum,
        "checksum_algo" => entry.checksum_algo,
        "source_url" => entry.source_url,
        "dependencies" => entry.dependencies,
        "installed_at" => entry.installed_at
      }
      {key, value}
    end)
    |> Map.new()
  end
end
