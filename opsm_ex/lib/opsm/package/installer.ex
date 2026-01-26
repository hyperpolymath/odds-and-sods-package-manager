# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Package.Installer do
  @moduledoc """
  Package installation and management.
  Handles unpacking, linking, and registering installed packages.
  """

  import Bitwise

  alias Opsm.Package.Downloader
  alias Opsm.Package.Transaction
  alias Opsm.Federation
  alias Opsm.Trust.Pipeline
  alias Opsm.Validation
  alias Opsm.Errors
  alias Opsm.Resolver
  alias Opsm.Lockfile

  @user_install_dir Path.expand("~/.local/share/opsm/packages")
  @system_install_dir "/usr/local/share/opsm/packages"
  @user_bin_dir Path.expand("~/.local/bin")
  @system_bin_dir "/usr/local/bin"
  @db_path Path.expand("~/.local/share/opsm/installed.json")

  @doc """
  Install a package from a registry.
  """
  def install(forth, package_name, opts \\ []) do
    version = Keyword.get(opts, :version, "latest")
    scope = Keyword.get(opts, :scope, :user)
    dry_run = Keyword.get(opts, :dry_run, false)

    # Validate inputs for security
    with {:ok, _} <- Validation.validate_package_name(package_name, forth),
         {:ok, _} <- Validation.validate_version(version) do
      IO.puts("Installing #{package_name}@#{version} from @#{forth}")
      IO.puts("")

      # Check toolchain
      case Federation.check_toolchain(forth) do
        {:error, info} ->
          error = Errors.missing_toolchain(forth, [info.message])
          Errors.print_error(error)
          {:error, :missing_toolchain}

        _ ->
          do_install(forth, package_name, version, scope, dry_run)
      end
    else
      {:error, reason} ->
        error = Errors.invalid_package_name(package_name, reason)
        Errors.print_error(error)
        {:error, {:validation_failed, reason}}
    end
  end

  @doc """
  Remove an installed package.
  """
  def remove(package_name, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    case find_installed(package_name) do
      nil ->
        {:error, Errors.format(Errors.package_not_found(package_name))}

      installed ->
        if dry_run do
          IO.puts("[DRY RUN] Would remove: #{installed.path}")
          {:ok, :dry_run}
        else
          do_remove(installed)
        end
    end
  end

  @doc """
  List installed packages.
  """
  def list_installed(opts \\ []) do
    forth = Keyword.get(opts, :forth)

    installed = load_installed_db()

    if forth do
      Enum.filter(installed, fn pkg -> pkg["forth"] == to_string(forth) end)
    else
      installed
    end
  end

  @doc """
  Check if a package is installed.
  """
  def installed?(package_name) do
    find_installed(package_name) != nil
  end

  @doc """
  Find installed package by name.
  """
  def find_installed(package_name) do
    installed = load_installed_db()
    Enum.find(installed, fn pkg -> pkg["name"] == package_name end)
  end

  # Internal functions

  defp do_install(forth, package_name, version, scope, dry_run) do
    # Build root dependency for resolver
    root_dep = %{
      name: package_name,
      constraint: if(version == "latest", do: "*", else: version),
      forth: forth
    }

    IO.puts("  Resolving dependencies for #{package_name}...")

    case Resolver.resolve([root_dep], forth: forth) do
      {:ok, resolution} ->
        # Resolution successful - we have a map of package_name => {version, ResolvedPackage}
        packages_to_install = Map.values(resolution)
        IO.puts("  Resolved #{length(packages_to_install)} package(s)")

        # Show dependency tree
        Enum.each(packages_to_install, fn {version, pkg} ->
          IO.puts("    - #{pkg.package}@#{version}")
        end)

        IO.puts("")

        # Install all packages in resolution order
        # TODO: Sort topologically to install dependencies before dependents
        install_resolved_packages(packages_to_install, scope, dry_run)

      {:error, reason} ->
        IO.puts("  ✗ Dependency resolution failed:")
        IO.puts("    #{reason}")
        {:error, Errors.format({:resolver, reason, "Check version constraints"})}
    end
  end

  defp install_resolved_packages(packages, scope, dry_run) do
    # Install each package
    results =
      Enum.map(packages, fn {version, package} ->
        IO.puts("")
        IO.puts("Installing #{package.package}@#{version}...")

        # Run trust pipeline
        IO.puts("  Running trust checks...")
        {:ok, trust_result} = Pipeline.verify(package)

        case handle_trust_result(trust_result, package, scope, dry_run) do
          {:ok, _} -> {:ok, package}
          {:ok, :dry_run} -> {:ok, :dry_run}
          {:error, reason} -> {:error, {package.package, reason}}
        end
      end)

    # Check if any failed
    failed = Enum.filter(results, fn r -> match?({:error, _}, r) end)

    if failed != [] do
      {:error, format_install_failures(failed)}
    else
      # Update lockfile with resolved packages
      update_lockfile_with_resolution(packages)
      {:ok, :all_installed}
    end
  end

  defp format_install_failures(failed) do
    failures =
      Enum.map(failed, fn {:error, {pkg, reason}} ->
        "  - #{pkg}: #{reason}"
      end)
      |> Enum.join("\n")

    "Failed to install packages:\n#{failures}"
  end

  defp update_lockfile_with_resolution(packages) do
    # Read existing lockfile or create new
    lockfile =
      case Lockfile.read() do
        {:ok, lf} -> lf
        {:error, :not_found} -> Lockfile.new()
        {:error, _} -> Lockfile.new()
      end

    # Add each package to lockfile
    updated_lockfile =
      Enum.reduce(packages, lockfile, fn {version, pkg}, acc ->
        dep_names = Map.keys(pkg.manifest.dependencies || %{})

        Lockfile.add_package(acc, %{
          name: pkg.package,
          version: version,
          forth: pkg.forth,
          checksum: pkg.checksum,
          checksum_algo: pkg.checksum_algo,
          source_url: pkg.tarball_url,
          dependencies: dep_names
        })
      end)

    # Write lockfile
    case Lockfile.write(updated_lockfile) do
      {:ok, _path} ->
        IO.puts("")
        IO.puts("Updated opsm.lock")
        :ok

      {:error, reason} ->
        IO.puts("")
        IO.puts("⚠ Failed to update lockfile: #{reason}")
        :ok
    end
  end

  defp handle_trust_result(trust_result, package, scope, dry_run) do
    case trust_result.overall do
      :failed ->
        IO.puts("  ✗ Trust pipeline failed")
        for warn <- trust_result.warnings do
          IO.puts("    - #{warn}")
        end
        {:error, Errors.format(Errors.trust_failed(package.package, trust_result.warnings))}

      :warning ->
        IO.puts("  ⚠ Trust pipeline warnings:")
        for warn <- trust_result.warnings do
          IO.puts("    - #{warn}")
        end
        IO.puts("  Proceeding with installation...")
        continue_install(package, scope, dry_run)

      _ ->
        IO.puts("  ✓ Trust checks passed")
        continue_install(package, scope, dry_run)
    end
  end

  defp continue_install(package, scope, dry_run) do
    if dry_run do
      IO.puts("[DRY RUN] Would download: #{package.tarball_url}")
      IO.puts("[DRY RUN] Would install to: #{install_dir(scope)}")
      {:ok, :dry_run}
    else
      # Start transaction for rollback support (F1)
      txn = Transaction.new(package.package)

      # Download
      IO.puts("")
      case Downloader.download(package) do
        {:ok, tarball_path} ->
          # Track downloaded file in transaction
          txn = Transaction.record_file(txn, tarball_path)

          # Unpack and install
          install_path = Path.join([install_dir(scope), to_string(package.forth), package.package])
          IO.puts("  Installing to: #{install_path}")

          # Create install directory with transaction tracking
          case Transaction.mkdir_p(txn, install_path) do
            {:ok, txn} ->
              case unpack(tarball_path, install_path, package.forth) do
                :ok ->
                  # Link binaries to PATH with safe symlinks (S5)
                  case link_binaries_safe(txn, install_path, package.forth, scope) do
                    {:ok, txn, linked_bins} ->
                      if linked_bins != [] do
                        IO.puts("  Linked #{length(linked_bins)} executable(s) to #{bin_dir(scope)}")
                      end

                      # Register in installed db
                      register_installed(package, scope, install_path, linked_bins)

                      # Mark transaction complete
                      _txn = Transaction.complete(txn)

                      IO.puts("")
                      IO.puts("✓ Installed #{package.package}@#{package.version}")
                      {:ok, package}

                    {:error, reason} ->
                      # Rollback on symlink failure
                      Transaction.rollback(txn)
                      {:error, Errors.format({:install, "Failed to link binaries: #{reason}", "Check permissions on #{bin_dir(scope)}"})}
                  end

                {:error, reason} ->
                  # Rollback on unpack failure
                  Transaction.rollback(txn)
                  {:error, Errors.format(Errors.unpack_failed(package.package, reason))}
              end

            {:error, reason} ->
              # Rollback on mkdir failure
              Transaction.rollback(txn)
              {:error, Errors.format({:install, "Failed to create install directory: #{reason}", "Check permissions"})}
          end

        {:error, reason} ->
          {:error, Errors.format(Errors.download_failed(package.package, reason))}
      end
    end
  end

  defp unpack(tarball_path, dest_path, forth) do
    File.mkdir_p!(dest_path)

    case forth do
      :npm -> unpack_npm(tarball_path, dest_path)
      :cargo -> unpack_crate(tarball_path, dest_path)
      :hex -> unpack_hex(tarball_path, dest_path)
      :pypi -> unpack_pypi(tarball_path, dest_path)
      _ -> unpack_generic(tarball_path, dest_path)
    end
  end

  defp unpack_npm(tarball_path, dest_path) do
    # npm packages are .tgz with a `package/` prefix
    case System.cmd("tar", ["-xzf", tarball_path, "-C", dest_path, "--strip-components=1"],
                    stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp unpack_crate(tarball_path, dest_path) do
    # Rust crates are .crate (gzipped tar) with package-version/ prefix
    case System.cmd("tar", ["-xzf", tarball_path, "-C", dest_path, "--strip-components=1"],
                    stderr_to_stdout: true) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp unpack_hex(tarball_path, dest_path) do
    # Hex packages are .tar containing contents.tar.gz
    # First extract the outer tar
    tmp_dir = Path.join(System.tmp_dir!(), "opsm_hex_#{:rand.uniform(100000)}")
    File.mkdir_p!(tmp_dir)

    case System.cmd("tar", ["-xf", tarball_path, "-C", tmp_dir], stderr_to_stdout: true) do
      {_, 0} ->
        # Now extract contents.tar.gz
        contents_tar = Path.join(tmp_dir, "contents.tar.gz")
        if File.exists?(contents_tar) do
          case System.cmd("tar", ["-xzf", contents_tar, "-C", dest_path], stderr_to_stdout: true) do
            {_, 0} ->
              File.rm_rf!(tmp_dir)
              :ok
            {error, _} ->
              File.rm_rf!(tmp_dir)
              {:error, error}
          end
        else
          File.rm_rf!(tmp_dir)
          {:error, "contents.tar.gz not found in hex package"}
        end

      {error, _} ->
        File.rm_rf!(tmp_dir)
        {:error, error}
    end
  end

  defp unpack_pypi(tarball_path, dest_path) do
    # Python packages are .tar.gz or .whl (zip) with package-version/ prefix
    if String.ends_with?(tarball_path, ".whl") do
      case System.cmd("unzip", ["-q", tarball_path, "-d", dest_path], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {error, _} -> {:error, error}
      end
    else
      case System.cmd("tar", ["-xzf", tarball_path, "-C", dest_path, "--strip-components=1"],
                      stderr_to_stdout: true) do
        {_, 0} -> :ok
        {error, _} -> {:error, error}
      end
    end
  end

  defp unpack_generic(tarball_path, dest_path) do
    cmd = cond do
      String.ends_with?(tarball_path, ".tar.gz") or String.ends_with?(tarball_path, ".tgz") ->
        ["tar", ["-xzf", tarball_path, "-C", dest_path]]
      String.ends_with?(tarball_path, ".tar") ->
        ["tar", ["-xf", tarball_path, "-C", dest_path]]
      String.ends_with?(tarball_path, ".zip") ->
        ["unzip", ["-q", tarball_path, "-d", dest_path]]
      true ->
        ["tar", ["-xzf", tarball_path, "-C", dest_path]]
    end

    case apply(System, :cmd, cmd ++ [[stderr_to_stdout: true]]) do
      {_, 0} -> :ok
      {error, _} -> {:error, error}
    end
  end

  defp install_dir(:user), do: @user_install_dir
  defp install_dir(:systemwide), do: @system_install_dir
  defp install_dir(_), do: @user_install_dir

  defp bin_dir(:user), do: @user_bin_dir
  defp bin_dir(:systemwide), do: @system_bin_dir
  defp bin_dir(_), do: @user_bin_dir

  # Safe version that uses Transaction for tracking and security checks (S5)
  defp link_binaries_safe(txn, install_path, forth, scope) do
    bin_target = bin_dir(scope)

    case Transaction.mkdir_p(txn, bin_target) do
      {:ok, txn} ->
        executables = find_executables(install_path, forth)
        link_executables_safe(txn, executables, bin_target, [])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp link_executables_safe(txn, [], _bin_target, acc) do
    {:ok, txn, Enum.reverse(acc)}
  end

  defp link_executables_safe(txn, [exe_path | rest], bin_target, acc) do
    exe_name = Path.basename(exe_path)
    link_path = Path.join(bin_target, exe_name)

    # Check if we need to remove existing link first
    case File.lstat(link_path) do
      {:ok, %{type: :symlink}} ->
        # Remove old symlink
        File.rm(link_path)
      {:ok, %{type: :regular}} ->
        # Regular file exists - don't overwrite, warn user
        IO.puts("    ⚠ Skipping #{exe_name}: regular file exists at #{link_path}")
        link_executables_safe(txn, rest, bin_target, acc)
      {:ok, %{type: :directory}} ->
        IO.puts("    ⚠ Skipping #{exe_name}: directory exists at #{link_path}")
        link_executables_safe(txn, rest, bin_target, acc)
      {:error, :enoent} ->
        # Doesn't exist - good
        :ok
      {:error, _} ->
        :ok
    end

    case Transaction.safe_symlink(txn, exe_path, link_path) do
      {:ok, txn} ->
        IO.puts("    → #{exe_name}")
        link_executables_safe(txn, rest, bin_target, [link_path | acc])

      {:error, reason} ->
        IO.puts("    ⚠ Failed to link #{exe_name}: #{reason}")
        # Continue with other executables, don't fail entire install
        link_executables_safe(txn, rest, bin_target, acc)
    end
  end

  defp find_executables(install_path, forth) do
    case forth do
      :npm -> find_npm_bins(install_path)
      :cargo -> find_cargo_bins(install_path)
      :hex -> find_hex_bins(install_path)
      :pypi -> find_pypi_bins(install_path)
      :gem -> find_gem_bins(install_path)
      _ -> find_generic_bins(install_path)
    end
  end

  defp find_npm_bins(install_path) do
    # npm packages declare bins in package.json
    package_json = Path.join(install_path, "package.json")

    if File.exists?(package_json) do
      case File.read(package_json) |> then(fn {:ok, c} -> Jason.decode(c); e -> e end) do
        {:ok, %{"bin" => bins}} when is_binary(bins) ->
          # Single binary with package name
          [Path.join(install_path, bins)]

        {:ok, %{"bin" => bins}} when is_map(bins) ->
          # Multiple binaries
          Enum.map(bins, fn {_name, path} -> Path.join(install_path, path) end)

        _ ->
          # Check for bin/ directory
          find_in_bin_dir(install_path)
      end
    else
      find_in_bin_dir(install_path)
    end
  end

  defp find_cargo_bins(install_path) do
    # Rust crates have src/main.rs or src/bin/*.rs
    # After build, binaries are in target/release/
    # For source installs, check Cargo.toml for [[bin]] sections
    cargo_toml = Path.join(install_path, "Cargo.toml")

    if File.exists?(cargo_toml) do
      case File.read(cargo_toml) do
        {:ok, content} ->
          # Parse bin names from Cargo.toml
          bins = Regex.scan(~r/\[\[bin\]\].*?name\s*=\s*"([^"]+)"/s, content)
          |> Enum.map(fn [_, name] -> name end)

          # Also check for default binary (same as package name)
          pkg_name = case Regex.run(~r/name\s*=\s*"([^"]+)"/, content) do
            [_, name] -> name
            _ -> nil
          end

          all_bins = if pkg_name && File.exists?(Path.join(install_path, "src/main.rs")) do
            [pkg_name | bins]
          else
            bins
          end

          # Return paths (these would need to be built)
          Enum.map(Enum.uniq(all_bins), fn name ->
            Path.join([install_path, "target", "release", name])
          end)
          |> Enum.filter(&File.exists?/1)

        _ -> []
      end
    else
      []
    end
  end

  defp find_hex_bins(install_path) do
    # Elixir packages typically don't have standalone binaries
    # Check for escript or mix tasks
    escript = Path.join(install_path, "escript")
    if File.exists?(escript), do: [escript], else: []
  end

  defp find_pypi_bins(install_path) do
    # Python packages have entry_points in setup.py/pyproject.toml
    # Or scripts in bin/ or scripts/
    scripts_dir = Path.join(install_path, "scripts")
    bin_dir = Path.join(install_path, "bin")

    cond do
      File.dir?(scripts_dir) -> list_executables(scripts_dir)
      File.dir?(bin_dir) -> list_executables(bin_dir)
      true -> []
    end
  end

  defp find_gem_bins(install_path) do
    # Ruby gems have executables in bin/ or exe/
    bin_dir = Path.join(install_path, "bin")
    exe_dir = Path.join(install_path, "exe")

    cond do
      File.dir?(exe_dir) -> list_executables(exe_dir)
      File.dir?(bin_dir) -> list_executables(bin_dir)
      true -> []
    end
  end

  defp find_generic_bins(install_path) do
    find_in_bin_dir(install_path)
  end

  defp find_in_bin_dir(install_path) do
    bin_dir = Path.join(install_path, "bin")
    if File.dir?(bin_dir) do
      list_executables(bin_dir)
    else
      []
    end
  end

  defp list_executables(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.map(&Path.join(dir, &1))
        |> Enum.filter(fn path ->
          case File.stat(path) do
            {:ok, %{type: :regular, mode: mode}} ->
              # Check if executable (any execute bit set)
              (mode &&& 0o111) != 0
            _ -> false
          end
        end)

      _ -> []
    end
  end

  defp register_installed(package, scope, install_path, linked_bins) do
    installed = load_installed_db()

    entry = %{
      "name" => package.package,
      "version" => package.version,
      "forth" => to_string(package.forth),
      "scope" => to_string(scope),
      "path" => install_path,
      "installed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "tarball_url" => package.tarball_url,
      "checksum" => package.checksum,
      "linked_bins" => linked_bins
    }

    # Remove existing entry for same package
    installed = Enum.reject(installed, fn pkg -> pkg["name"] == package.package end)
    updated = [entry | installed]

    save_installed_db(updated)
  end

  defp do_remove(installed) do
    IO.puts("Removing: #{installed["name"]}@#{installed["version"]}")

    # Unlink binaries first
    linked_bins = Map.get(installed, "linked_bins", [])
    if linked_bins != [] do
      IO.puts("  Unlinking #{length(linked_bins)} executable(s)...")
      Enum.each(linked_bins, fn link_path ->
        case File.rm(link_path) do
          :ok -> IO.puts("    ✓ #{Path.basename(link_path)}")
          {:error, :enoent} -> :ok  # Already gone
          {:error, reason} -> IO.puts("    ⚠ Failed to unlink #{link_path}: #{reason}")
        end
      end)
    end

    # Remove files
    case File.rm_rf(installed["path"]) do
      {:ok, _} ->
        # Update database
        db = load_installed_db()
        updated = Enum.reject(db, fn pkg -> pkg["name"] == installed["name"] end)
        save_installed_db(updated)
        IO.puts("✓ Removed #{installed["name"]}")
        :ok

      {:error, reason, path} ->
        {:error, Errors.format({:install, "Failed to remove #{path}: #{reason}", "Check file permissions"})}
    end
  end

  defp load_installed_db do
    case File.read(@db_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> data
          {:error, _} -> []
        end

      {:error, _} -> []
    end
  end

  defp save_installed_db(data) do
    @db_path |> Path.dirname() |> File.mkdir_p!()
    File.write!(@db_path, Jason.encode!(data, pretty: true))
  end
end
