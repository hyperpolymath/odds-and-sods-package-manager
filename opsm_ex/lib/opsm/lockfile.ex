# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Lockfile do
  @moduledoc """
  Lock file management for reproducible package installations.

  The lock file (opsm.lock) records:
  - Exact versions of all installed packages
  - Checksums for integrity verification (BLAKE2b for performance)
  - Lockfile integrity hash (SHA3-512 for long-term security)
  - Dependency tree structure
  - Installation timestamps

  This enables:
  - Reproducible installs across machines
  - Faster installs (skip resolution, use cached versions)
  - Dependency auditing
  - Tamper detection (lockfile integrity verification)

  Security features (v1.0.1+):
  - BLAKE2b package checksums (fast, secure)
  - SHA3-512 lockfile integrity hash (post-quantum, FIPS 202)
  - Optional ChaCha20-Poly1305 lockfile encryption
  """

  alias Opsm.Crypto.Hash
  alias Opsm.Crypto.Symmetric

  @lockfile_name "opsm.lock"
  @lockfile_version "2"  # v2: Added crypto integration

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
    packages: %{String.t() => package_entry()},
    integrity_hash: String.t() | nil,
    integrity_algo: String.t() | nil
  }

  @doc """
  Read the lock file from the current directory or specified path.
  Returns {:ok, lockfile} or {:error, reason}.

  Options:
  - decrypt: If true, decrypt the lockfile with ChaCha20-Poly1305
  - key: Decryption key (required if decrypt: true)
  - verify_integrity: If true, verify SHA3-512 integrity hash (default: true)
  """
  def read(path \\ @lockfile_name, opts \\ []) do
    with {:ok, content} <- File.read(path),
         {:ok, json_content} <- decrypt_if_needed(content, opts),
         {:ok, lockfile} <- parse_lockfile(json_content),
         {:ok, verified_lockfile} <- verify_integrity_if_needed(lockfile, opts) do
      {:ok, verified_lockfile}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decrypt_if_needed(content, opts) do
    if Keyword.get(opts, :decrypt, false) do
      key = Keyword.fetch!(opts, :key)
      context = "opsm-lockfile-v#{@lockfile_version}"

      case Symmetric.decrypt(content, key, context) do
        {:ok, decrypted} -> {:ok, decrypted}
        {:error, reason} -> {:error, "Lockfile decryption failed: #{reason}"}
      end
    else
      {:ok, content}
    end
  end

  defp verify_integrity_if_needed(lockfile, opts) do
    if Keyword.get(opts, :verify_integrity, true) do
      case verify_integrity(lockfile) do
        :ok -> {:ok, lockfile}
        {:ok, :no_integrity_hash} -> {:ok, lockfile}  # Allow old lockfiles without integrity
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, lockfile}
    end
  end

  @doc """
  Write a lock file to the current directory or specified path.

  Options:
  - encrypt: If true, encrypt the lockfile with ChaCha20-Poly1305
  - key: Encryption key (required if encrypt: true)
  - compute_integrity: If true, compute SHA3-512 integrity hash (default: true)
  """
  def write(lockfile, path \\ @lockfile_name, opts \\ []) do
    # Compute integrity hash before writing (SHA3-512 for long-term security)
    lockfile_with_integrity = if Keyword.get(opts, :compute_integrity, true) do
      compute_integrity_hash(lockfile)
    else
      lockfile
    end

    content = serialize_lockfile(lockfile_with_integrity)

    # Optionally encrypt the lockfile
    final_content = if Keyword.get(opts, :encrypt, false) do
      key = Keyword.fetch!(opts, :key)
      context = "opsm-lockfile-v#{@lockfile_version}"

      case Symmetric.encrypt(content, key, context) do
        {:ok, encrypted} -> encrypted
        {:error, reason} -> raise "Lockfile encryption failed: #{reason}"
      end
    else
      content
    end

    case File.write(path, final_content) do
      :ok ->
        {:ok, path}

      {:error, reason} ->
        {:error, "Failed to write lock file: #{reason}"}
    end
  end

  @doc """
  Compute SHA3-512 integrity hash for the entire lockfile.

  Uses SHA3-512 for long-term security and post-quantum resistance.
  """
  def compute_integrity_hash(lockfile) do
    # Serialize lockfile without integrity_hash field
    data = %{
      "version" => lockfile.version,
      "generated_at" => lockfile.generated_at,
      "packages" => serialize_packages(lockfile.packages)
    }

    json = Jason.encode!(data, pretty: true)
    hash = Hash.hash_provenance(json)

    %{lockfile |
      integrity_hash: hash,
      integrity_algo: "sha3-512"
    }
  end

  @doc """
  Verify the lockfile integrity hash.

  Returns :ok if valid, {:error, reason} otherwise.
  """
  def verify_integrity(lockfile) do
    case lockfile.integrity_hash do
      nil ->
        {:ok, :no_integrity_hash}

      stored_hash ->
        # Recompute integrity hash
        recomputed = compute_integrity_hash(%{lockfile | integrity_hash: nil})

        if recomputed.integrity_hash == stored_hash do
          :ok
        else
          {:error, "Lockfile integrity verification failed (tampering detected)"}
        end
    end
  end

  @doc """
  Create a new empty lockfile structure.
  """
  def new do
    %{
      version: @lockfile_version,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      packages: %{},
      integrity_hash: nil,
      integrity_algo: "sha3-512"
    }
  end

  @doc """
  Add or update a package entry in the lockfile.

  Defaults to BLAKE2b checksums for performance (v1.0.1+).
  Use SHA3-512 for long-term archival or provenance tracking.
  """
  def add_package(lockfile, package_info) do
    entry = %{
      name: package_info.name,
      version: package_info.version,
      forth: package_info.forth,
      checksum: Map.get(package_info, :checksum),
      checksum_algo: Map.get(package_info, :checksum_algo, "blake2b"),  # v1.0.1: Default to BLAKE2b
      source_url: Map.get(package_info, :source_url),
      dependencies: Map.get(package_info, :dependencies, []),
      installed_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    key = "#{package_info.name}@#{package_info.forth}"
    packages = Map.put(lockfile.packages, key, entry)

    %{lockfile |
      packages: packages,
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      integrity_hash: nil  # Will be computed on write
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
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      integrity_hash: nil  # Will be recomputed on write
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
  Get packages by name (across all forths).
  """
  def packages_for_name(lockfile, name) do
    lockfile.packages
    |> Map.values()
    |> Enum.filter(fn p -> p.name == name end)
    |> Enum.sort_by(& &1.forth)
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
          packages: parse_packages(Map.get(data, "packages", %{})),
          integrity_hash: Map.get(data, "integrity_hash"),
          integrity_algo: Map.get(data, "integrity_algo", "sha3-512")
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
      "packages" => serialize_packages(lockfile.packages),
      "integrity_hash" => lockfile.integrity_hash,
      "integrity_algo" => lockfile.integrity_algo
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
