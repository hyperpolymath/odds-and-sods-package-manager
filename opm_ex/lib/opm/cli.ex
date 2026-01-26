# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.CLI do
  @moduledoc """
  CLI entry point for OPM - Odds-and-sods Package Manager.

  Federated package management with features from dnf, apt, nala, rpm.
  """

  alias Opm.Config
  alias Opm.Wiring
  alias Opm.Federation
  alias Opm.Errors
  alias Opm.Maintenance


  def main(args) do
    args
    |> parse_args()
    |> run()
  end

  defp parse_args(args) do
    {opts, args, _invalid} = OptionParser.parse(args,
      strict: [
        help: :boolean,
        version: :string,
        allow: :string,
        systemwide: :boolean,
        user: :boolean,
        global: :boolean,
        yes: :boolean,
        quiet: :boolean,
        verbose: :boolean,
        dry_run: :boolean,
        refresh: :boolean,
        downloadonly: :boolean,
        installed: :boolean,
        available: :boolean,
        updates: :boolean,
        obsoletes: :boolean,
        all: :boolean,
        recursive: :boolean,
        reverse: :boolean,
        json: :boolean,
        limit: :integer,
        native: :boolean,
        dev: :boolean
      ],
      aliases: [
        h: :help,
        v: :version,
        y: :yes,
        q: :quiet,
        n: :dry_run,
        g: :global,
        D: :dev
      ]
    )

    case args do
      # Help
      ["help" | _] -> {:help, opts}
      ["--help" | _] -> {:help, opts}
      ["-h" | _] -> {:help, opts}
      [] -> {:help, opts}

      # Status & Info
      ["status" | _] -> {:status, opts}
      ["repolist" | _] -> {:repolist, opts}

      # Install/Remove
      ["install", "@" <> forth, package | _] -> {:install, forth, package, opts}
      ["install", package | _] -> {:install, nil, package, opts}
      ["install"] -> {:error, "install requires a package argument"}

      ["remove", package | _] -> {:remove, package, opts}
      ["uninstall", package | _] -> {:remove, package, opts}
      ["remove"] -> {:error, "remove requires a package argument"}

      ["reinstall", package | _] -> {:reinstall, package, opts}

      # Update/Upgrade
      ["update" | packages] -> {:update, packages, opts}
      ["upgrade" | packages] -> {:update, packages, opts}
      ["check-update" | _] -> {:check_update, opts}

      # Search/Query
      ["search", query | _] -> {:search, query, opts}
      ["search"] -> {:error, "search requires a query"}

      ["info", package | _] -> {:info, package, opts}
      ["show", package | _] -> {:info, package, opts}
      ["info"] -> {:error, "info requires a package argument"}

      ["list" | rest] -> {:list, rest, opts}

      ["provides", file | _] -> {:provides, file, opts}
      ["whatprovides", file | _] -> {:provides, file, opts}

      ["depends", package | _] -> {:depends, package, opts}
      ["deplist", package | _] -> {:depends, package, opts}

      ["rdepends", package | _] -> {:rdepends, package, opts}
      ["repoquery", "--whatrequires", package | _] -> {:rdepends, package, opts}

      # Pin/Hold
      ["pin", package, version | _] -> {:pin, package, version, opts}
      ["pin", package | _] -> {:pin, package, nil, opts}
      ["hold", package | _] -> {:pin, package, nil, opts}
      ["pin"] -> {:error, "pin requires a package argument"}

      ["unpin", package | _] -> {:unpin, package, opts}
      ["unhold", package | _] -> {:unpin, package, opts}

      # Maintenance
      ["clean", what | _] -> {:clean, what, opts}
      ["clean"] -> {:clean, "all", opts}

      ["autoremove" | _] -> {:autoremove, opts}

      ["history" | rest] -> {:history, rest, opts}

      ["download", package | _] -> {:download, package, opts}
      ["download"] -> {:error, "download requires a package argument"}

      ["check" | _] -> {:check, opts}
      ["verify" | _] -> {:check, opts}

      # Publish/Audit (OPM-specific)
      ["publish", path | _] -> {:publish, path, opts}
      ["publish"] -> {:error, "publish requires a path argument"}

      ["audit", package | _] -> {:audit, package, opts}
      ["audit"] -> {:error, "audit requires a package argument"}

      # Federation
      ["ports" | _] -> {:ports, opts}
      ["convert", path | _] -> {:convert, path, opts}
      ["export", package, target | _] -> {:export, package, target, opts}

      # Unknown
      [cmd | _] -> {:error, "Unknown command: #{cmd}"}
    end
  end

  defp run({:help, _opts}) do
    IO.puts("""
    opsm - Odds-and-sods Package Manager

    Federated multi-registry package manager with trust pipeline.

    USAGE:
      opsm <command> [@forth] [package] [options]

    PACKAGE COMMANDS:
      install [@forth] <pkg>   Install package (optionally from specific registry)
      remove <package>         Remove an installed package
      reinstall <package>      Reinstall a package
      update [packages...]     Update packages (all if none specified)
      check-update             Check for available updates

    QUERY COMMANDS:
      search <query>           Search for packages across registries
      info <package>           Show detailed package information
      list [--installed|--available|--updates|--obsoletes]
      provides <file>          Find which package provides a file
      depends <package>        Show package dependencies
      rdepends <package>       Show reverse dependencies (what depends on this)

    VERSION CONTROL:
      pin <package> [version]  Pin package to prevent updates (like apt hold)
      unpin <package>          Remove version pin

    MAINTENANCE:
      clean [all|cache|metadata|packages]  Clean cached data
      autoremove               Remove unused dependencies
      history [list|info|undo|redo]        Transaction history
      download <package>       Download without installing
      check                    Verify package integrity

    PUBLISHING (trust pipeline):
      publish <path>           Publish through claim-forge -> checky-monkey -> registry
      audit <package>          Run sustainability + license analysis

    SYSTEM:
      status                   Show service status and configuration
      repolist                 List configured registries (forths)

    FEDERATION:
      ports                    List available system package managers
      convert <manifest>       Convert manifest (Nickel/Idris2/npm/Cargo/etc.)
      export <pkg> <target>    Export package to system format (deb/rpm/etc.)

    OPTIONS:
      --version <ver>          Version: 1.2.3, @next, @latest, @stable
      --allow <channel>        Allow: snapshot, alpha, beta, rc, esr
      --systemwide             Install system-wide
      --user                   Install for current user (default)
      -g, --global             Global install (native mode)
      -D, --dev                Development dependency
      --native                 Use native toolchain (npm, cargo, mix, pip)
      -y, --yes                Assume yes to prompts
      -q, --quiet              Minimal output
      -n, --dry-run            Show what would be done
      --refresh                Refresh metadata before operation
      --downloadonly           Download only, don't install
      --json                   Output in JSON format
      --recursive              Include transitive dependencies
      --reverse                Reverse order (for depends)

    FORTHS (language ecosystems):
      @npm      Node.js packages (npmjs.com)
      @cargo    Rust crates (crates.io)
      @hex      Elixir/Erlang (hex.pm)
      @pypi     Python (pypi.org)
      @gem      Ruby (rubygems.org)
      @nuget    .NET (nuget.org)
      @maven    Java/JVM (maven central)
      @pub      Dart/Flutter (pub.dev)
      @go       Go modules (proxy.golang.org)

    CONNECTION PORTS (system package managers):
      @deb      Debian/Ubuntu (apt)
      @rpm      Fedora/RHEL (dnf/yum)
      @pacman   Arch Linux (pacman)
      @winget   Windows (winget)
      @choco    Windows (Chocolatey)
      @scoop    Windows (Scoop)
      @homebrew macOS/Linux (brew)
      @nix      NixOS/any (nix-env)
      @guix     Guix System (guix)

    EXAMPLES:
      opsm install lodash                      # From default/detected registry
      opsm install @npm lodash --version 4.17  # Specific version from npm
      opsm install @cargo tokio --allow rc     # Release candidate
      opsm install @hex phoenix --systemwide   # System-wide
      opsm install @dnf htop                   # Via system package manager
      opsm search "http client"                # Search across all forths
      opsm list --updates                      # Show available updates
      opsm depends @npm express --recursive    # Full dependency tree
      opsm pin lodash 4.17.21                  # Lock version
      opsm history undo                        # Undo last transaction
      opsm publish ./my-package
      opsm audit express
      opsm ports                               # List available system PMs
      opsm convert package.ncl                 # Convert Nickel manifest
      opsm export myapp deb                    # Export to .deb format

    CONFIG:
      $OPM_CONFIG > ./opm.toml > ~/.config/opm/opm.toml
    """)
  end

  defp run({:status, _opts}) do
    config = Config.load_config_or_example()
    :ok = Wiring.run_status(config)
    System.halt(0)
  end

  defp run({:repolist, opts}) do
    json? = Keyword.get(opts, :json, false)

    forths = [
      %{name: "npm", url: "https://registry.npmjs.org", status: "enabled"},
      %{name: "cargo", url: "https://crates.io", status: "enabled"},
      %{name: "hex", url: "https://hex.pm", status: "enabled"},
      %{name: "pypi", url: "https://pypi.org", status: "enabled"},
      %{name: "gem", url: "https://rubygems.org", status: "enabled"},
      %{name: "nuget", url: "https://api.nuget.org", status: "enabled"},
      %{name: "maven", url: "https://repo1.maven.org", status: "enabled"},
      %{name: "pub", url: "https://pub.dev", status: "enabled"},
      %{name: "go", url: "https://proxy.golang.org", status: "enabled"}
    ]

    if json? do
      IO.puts(Jason.encode!(forths, pretty: true))
    else
      IO.puts("Configured Forths (Registries)")
      IO.puts("==============================")
      for f <- forths do
        IO.puts("  @#{f.name}\t#{f.url}\t[#{f.status}]")
      end
    end
    System.halt(0)
  end

  defp run({:publish, path, _opts}) do
    config = Config.load_config_or_example()
    case Wiring.run_publish(config, path) do
      {:ok, _} -> System.halt(0)
      {:error, reason} ->
        Errors.print_error({:internal, "Publish failed: #{reason}", "Check path and credentials"})
        System.halt(1)
    end
  end

  defp run({:audit, package, _opts}) do
    config = Config.load_config_or_example()
    {:ok, _} = Wiring.run_audit(config, package)
    System.halt(0)
  end

  defp run({:install, forth, package, opts}) do
    version = Keyword.get(opts, :version, "latest")
    allow = Keyword.get(opts, :allow)
    dry_run? = Keyword.get(opts, :dry_run, false)
    json? = Keyword.get(opts, :json, false)
    native? = Keyword.get(opts, :native, false)
    global? = Keyword.get(opts, :global, false)
    dev? = Keyword.get(opts, :dev, false)
    scope = cond do
      Keyword.get(opts, :systemwide) -> "systemwide"
      true -> "user"
    end

    if dry_run?, do: IO.puts("[DRY RUN]")

    if forth do
      # Specific registry requested
      do_install_from_forth(forth, package, version, allow, scope, dry_run?, json?, native?, global?, dev?)
    else
      # No registry specified - discover across all
      do_install_discover(package, version, allow, scope, dry_run?, json?)
    end
  end

  defp run({:remove, package, opts}) do
    alias Opm.Package.Installer

    dry_run? = Keyword.get(opts, :dry_run, false)

    case Installer.remove(package, dry_run: dry_run?) do
      :ok -> System.halt(0)
      {:ok, :dry_run} -> System.halt(0)
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({:reinstall, package, _opts}) do
    IO.puts("Reinstalling: #{package}")
    IO.puts("⊘ Reinstall not yet implemented")
    System.halt(0)
  end

  defp run({:update, packages, opts}) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    if dry_run?, do: IO.puts("[DRY RUN]")

    if packages == [] do
      IO.puts("Updating all packages...")
    else
      IO.puts("Updating: #{Enum.join(packages, ", ")}")
    end
    IO.puts("⊘ Update not yet implemented")
    System.halt(0)
  end

  defp run({:check_update, _opts}) do
    IO.puts("Checking for updates...")
    IO.puts("⊘ Check-update not yet implemented")
    System.halt(0)
  end

  defp run({:search, query, opts}) do
    alias Opm.Registries.Registry

    json? = Keyword.get(opts, :json, false)
    limit = Keyword.get(opts, :limit, 10)

    IO.puts("Searching for: #{query}")
    IO.puts("")

    results = Registry.search_all(query, limit: limit)

    if json? do
      IO.puts(Jason.encode!(results, pretty: true))
    else
      total = Enum.reduce(results, 0, fn {_, pkgs}, acc -> acc + length(pkgs) end)

      if total == 0 do
        IO.puts("No packages found matching '#{query}'")
      else
        for {forth, packages} <- results, packages != [] do
          IO.puts("@#{forth}:")
          for pkg <- Enum.take(packages, 5) do
            name = pkg[:name] || pkg["name"]
            version = pkg[:version] || pkg["version"] || ""
            desc = pkg[:description] || pkg["description"] || ""
            desc_short = if String.length(desc) > 60, do: String.slice(desc, 0, 57) <> "...", else: desc
            IO.puts("  #{name}@#{version}")
            if desc_short != "", do: IO.puts("    #{desc_short}")
          end
          IO.puts("")
        end
      end
    end

    System.halt(0)
  end

  defp run({:info, package, opts}) do
    alias Opm.Registries.Registry

    json? = Keyword.get(opts, :json, false)

    IO.puts("Fetching info for: #{package}")
    IO.puts("")

    # Check all registries for the package
    results = Registry.fetch_all(package)

    if json? do
      data = Enum.map(results, fn {forth, pkg} ->
        %{
          forth: forth,
          name: pkg.package,
          version: pkg.version,
          description: pkg.manifest.description,
          license: pkg.manifest.license,
          homepage: pkg.manifest.homepage,
          repository: pkg.manifest.repository,
          tarball_url: pkg.tarball_url
        }
      end)
      IO.puts(Jason.encode!(data, pretty: true))
    else
      if map_size(results) == 0 do
        Errors.print_error(Errors.package_not_found(package))
      else
        for {forth, pkg} <- results do
          IO.puts("@#{forth}")
          IO.puts("  Name:        #{pkg.package}")
          IO.puts("  Version:     #{pkg.version}")
          if pkg.manifest.description, do: IO.puts("  Description: #{pkg.manifest.description}")
          if pkg.manifest.license, do: IO.puts("  License:     #{pkg.manifest.license}")
          if pkg.manifest.homepage, do: IO.puts("  Homepage:    #{pkg.manifest.homepage}")
          if pkg.manifest.repository, do: IO.puts("  Repository:  #{pkg.manifest.repository}")
          if pkg.tarball_url, do: IO.puts("  Tarball:     #{pkg.tarball_url}")

          # Show dependencies count
          deps_count = map_size(pkg.manifest.dependencies)
          dev_deps_count = map_size(pkg.manifest.dev_dependencies)
          if deps_count > 0 or dev_deps_count > 0 do
            IO.puts("  Dependencies: #{deps_count} (#{dev_deps_count} dev)")
          end

          IO.puts("")
        end
      end
    end

    System.halt(0)
  end

  defp run({:list, args, opts}) do
    alias Opm.Package.Installer

    json? = Keyword.get(opts, :json, false)
    filter = cond do
      Keyword.get(opts, :installed) -> :installed
      Keyword.get(opts, :available) -> :available
      Keyword.get(opts, :updates) -> :updates
      Keyword.get(opts, :obsoletes) -> :obsoletes
      "installed" in args -> :installed
      "available" in args -> :available
      "updates" in args -> :updates
      true -> :installed
    end

    case filter do
      :installed ->
        installed = Installer.list_installed()

        if json? do
          IO.puts(Jason.encode!(installed, pretty: true))
        else
          if installed == [] do
            IO.puts("No packages installed via opsm")
          else
            IO.puts("Installed packages:")
            IO.puts("")
            for pkg <- installed do
              IO.puts("  #{pkg["name"]}@#{pkg["version"]} (@#{pkg["forth"]})")
              IO.puts("    Installed: #{pkg["installed_at"]}")
              IO.puts("    Path: #{pkg["path"]}")
              IO.puts("")
            end
          end
        end

      :updates ->
        IO.puts("Checking for updates...")
        installed = Installer.list_installed()

        for pkg <- installed do
          forth = String.to_atom(pkg["forth"])
          case Opm.Registries.Registry.fetch(forth, pkg["name"]) do
            {:ok, latest} ->
              if latest.version != pkg["version"] do
                IO.puts("  #{pkg["name"]}: #{pkg["version"]} -> #{latest.version}")
              end
            _ -> :ok
          end
        end

      _ ->
        IO.puts("⊘ #{filter} listing not yet implemented")
    end

    System.halt(0)
  end

  defp run({:provides, file, _opts}) do
    IO.puts("Finding package that provides: #{file}")
    IO.puts("⊘ Provides not yet implemented")
    System.halt(0)
  end

  defp run({:depends, package, opts}) do
    alias Opm.Resolver
    alias Opm.Lockfile

    recursive? = Keyword.get(opts, :recursive, false)
    json? = Keyword.get(opts, :json, false)

    IO.puts("Dependencies for: #{package}#{if recursive?, do: " (recursive)", else: ""}")
    IO.puts("")

    # Try to read from lockfile first
    case Lockfile.read() do
      {:ok, lockfile} ->
        show_dependencies_from_lockfile(lockfile, package, recursive?, json?)

      {:error, :not_found} ->
        # No lockfile, need to resolve
        IO.puts("No lockfile found. Resolving dependencies...")
        IO.puts("")

        root_dep = %{name: package, constraint: "*", forth: :npm}

        case Resolver.resolve([root_dep], forth: :npm) do
          {:ok, resolution} ->
            show_dependencies_from_resolution(resolution, package, recursive?, json?)

          {:error, reason} ->
            IO.puts(:stderr, "Error resolving dependencies: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error reading lockfile: #{reason}")
        System.halt(1)
    end

    System.halt(0)
  end

  defp run({:rdepends, package, opts}) do
    alias Opm.Lockfile

    json? = Keyword.get(opts, :json, false)

    IO.puts("Reverse dependencies for: #{package}")
    IO.puts("")

    case Lockfile.read() do
      {:ok, lockfile} ->
        # Find packages that depend on this one
        dependents =
          Lockfile.list_packages(lockfile)
          |> Enum.filter(fn pkg ->
            Enum.member?(pkg.dependencies || [], package)
          end)

        if json? do
          data =
            Enum.map(dependents, fn pkg ->
              %{name: pkg.name, version: pkg.version}
            end)

          IO.puts(Jason.encode!(data, pretty: true))
        else
          if dependents == [] do
            IO.puts("No packages depend on #{package}")
          else
            IO.puts("Packages that depend on #{package}:")
            Enum.each(dependents, fn pkg ->
              IO.puts("  - #{pkg.name}@#{pkg.version}")
            end)
          end
        end

      {:error, :not_found} ->
        IO.puts(:stderr, "No lockfile found. Install packages first.")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error reading lockfile: #{reason}")
        System.halt(1)
    end

    System.halt(0)
  end

  defp show_dependencies_from_lockfile(lockfile, package, recursive?, json?) do
    case Opm.Lockfile.packages_for_name(lockfile, package) do
      [] ->
        IO.puts("Package #{package} not found in lockfile")

      [pkg | _] ->
        if recursive? do
          # Collect all transitive dependencies
          all_deps = collect_transitive_deps(lockfile, [package], MapSet.new())

          if json? do
            IO.puts(Jason.encode!(MapSet.to_list(all_deps), pretty: true))
          else
            IO.puts("All dependencies (#{MapSet.size(all_deps)}):")
            all_deps
            |> MapSet.to_list()
            |> Enum.sort()
            |> Enum.each(fn dep -> IO.puts("  - #{dep}") end)
          end
        else
          # Direct dependencies only
          deps = pkg.dependencies || []

          if json? do
            IO.puts(Jason.encode!(deps, pretty: true))
          else
            if deps == [] do
              IO.puts("No direct dependencies")
            else
              IO.puts("Direct dependencies:")
              Enum.each(deps, fn dep -> IO.puts("  - #{dep}") end)
            end
          end
        end
    end
  end

  defp show_dependencies_from_resolution(resolution, package, recursive?, json?) do
    case Map.get(resolution, package) do
      nil ->
        IO.puts("Package #{package} not found in resolution")

      {_version, resolved_pkg} ->
        deps = Map.keys(resolved_pkg.manifest.dependencies || %{})

        if recursive? do
          # Show all packages in resolution (excluding root)
          all_packages =
            resolution
            |> Map.keys()
            |> Enum.reject(fn name -> name == package end)
            |> Enum.sort()

          if json? do
            IO.puts(Jason.encode!(all_packages, pretty: true))
          else
            IO.puts("All dependencies (#{length(all_packages)}):")
            Enum.each(all_packages, fn name ->
              {version, _} = Map.get(resolution, name)
              IO.puts("  - #{name}@#{version}")
            end)
          end
        else
          # Direct dependencies only
          if json? do
            IO.puts(Jason.encode!(deps, pretty: true))
          else
            if deps == [] do
              IO.puts("No direct dependencies")
            else
              IO.puts("Direct dependencies:")
              Enum.each(deps, fn dep -> IO.puts("  - #{dep}") end)
            end
          end
        end
    end
  end

  defp collect_transitive_deps(lockfile, to_visit, visited) do
    case to_visit do
      [] ->
        visited

      [pkg_name | rest] ->
        if MapSet.member?(visited, pkg_name) do
          collect_transitive_deps(lockfile, rest, visited)
        else
          case Opm.Lockfile.packages_for_name(lockfile, pkg_name) do
            [] ->
              collect_transitive_deps(lockfile, rest, visited)

            [pkg | _] ->
              deps = pkg.dependencies || []
              new_visited = MapSet.put(visited, pkg_name)
              new_to_visit = rest ++ deps
              collect_transitive_deps(lockfile, new_to_visit, new_visited)
          end
        end
    end
  end

  defp run({:pin, package, version, _opts}) do
    :ok = Maintenance.pin(package, version)
    System.halt(0)
  end

  defp run({:unpin, package, _opts}) do
    case Maintenance.unpin(package) do
      :ok -> System.halt(0)
      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:clean, what, opts}) do
    dry_run = Keyword.get(opts, :dry_run, false)

    case Maintenance.clean(what, dry_run: dry_run) do
      {:ok, _} -> System.halt(0)
      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:autoremove, opts}) do
    dry_run = Keyword.get(opts, :dry_run, false)
    {:ok, _} = Maintenance.autoremove(dry_run: dry_run)
    System.halt(0)
  end

  defp run({:history, args, opts}) do
    json? = Keyword.get(opts, :json, false)
    action = List.first(args) || "list"

    case action do
      "list" ->
        history = Maintenance.list_history()

        if json? do
          IO.puts(Jason.encode!(history, pretty: true))
        else
          if history == [] do
            IO.puts("No history recorded")
          else
            IO.puts("Recent operations:")
            IO.puts("")
            for entry <- history do
              IO.puts("  #{entry["id"]} | #{entry["timestamp"]} | #{entry["operation"]}")
              if entry["details"]["package"] do
                IO.puts("    Package: #{entry["details"]["package"]}")
              end
            end
          end
        end
        System.halt(0)

      "undo" ->
        case Maintenance.undo_last() do
          {:ok, _, _} -> System.halt(0)
          {:error, reason} ->
            Errors.print_error({:error, reason})
            System.halt(1)
        end

      "info" ->
        id = Enum.at(args, 1)
        if id do
          case Maintenance.get_history_entry(id) do
            nil ->
              IO.puts("History entry not found: #{id}")
              System.halt(1)
            entry ->
              IO.puts(Jason.encode!(entry, pretty: true))
              System.halt(0)
          end
        else
          IO.puts("Usage: opsm history info <id>")
          System.halt(1)
        end

      _ ->
        IO.puts("Unknown history action: #{action}")
        IO.puts("Available: list, undo, info")
        System.halt(1)
    end
  end

  defp run({:download, package, _opts}) do
    alias Opm.Registries.Registry
    alias Opm.Package.Downloader

    IO.puts("Downloading: #{package}")
    IO.puts("")

    # Find in all registries
    results = Registry.fetch_all(package)

    if map_size(results) == 0 do
      Errors.print_error(Errors.package_not_found(package))
      System.halt(1)
    end

    # Download from first available
    {forth, pkg} = Enum.at(results, 0)
    IO.puts("Found in @#{forth}: #{pkg.package}@#{pkg.version}")

    case Downloader.download(pkg) do
      {:ok, path} ->
        IO.puts("")
        IO.puts("✓ Downloaded to: #{path}")
        System.halt(0)

      {:error, reason} ->
        Errors.print_error(Errors.download_failed(package, reason))
        System.halt(1)
    end
  end

  defp run({:check, _opts}) do
    IO.puts("Verifying package integrity...")
    IO.puts("⊘ Check not yet implemented")
    System.halt(0)
  end

  defp run({:ports, opts}) do
    json? = Keyword.get(opts, :json, false)
    available = Federation.available_connection_ports()

    if json? do
      data = Enum.map(available, fn {name, info} ->
        %{name: name, command: info.command, path: info.path}
      end)
      IO.puts(Jason.encode!(data, pretty: true))
    else
      IO.puts("Available Connection Ports (System Package Managers)")
      IO.puts("====================================================")
      if map_size(available) == 0 do
        IO.puts("  No system package managers detected")
      else
        for {name, info} <- available do
          IO.puts("  @#{name}\t#{info.command}\t(#{info.path})")
        end
      end
      IO.puts("")
      IO.puts("Use 'opsm install @<port> <package>' to install via system PM")
    end
    System.halt(0)
  end

  defp run({:convert, path, opts}) do
    json? = Keyword.get(opts, :json, false)
    IO.puts("Converting manifest: #{path}")

    case Federation.convert_manifest(path) do
      {:ok, manifest} ->
        if json? do
          # Convert struct to map for JSON encoding
          data = Map.from_struct(manifest)
          IO.puts(Jason.encode!(data, pretty: true))
        else
          IO.puts("")
          IO.puts("Name:        #{manifest.name}")
          IO.puts("Version:     #{manifest.version}")
          if manifest.description, do: IO.puts("Description: #{manifest.description}")
          if manifest.license, do: IO.puts("License:     #{manifest.license}")
          if manifest.repository, do: IO.puts("Repository:  #{manifest.repository}")
          if manifest.authors != [], do: IO.puts("Authors:     #{Enum.join(manifest.authors, ", ")}")
          if manifest.keywords != [], do: IO.puts("Keywords:    #{Enum.join(manifest.keywords, ", ")}")
          IO.puts("")
          IO.puts("Dependencies: #{map_size(manifest.dependencies)}")
          IO.puts("Dev deps:     #{map_size(manifest.dev_dependencies)}")
        end
        System.halt(0)

      {:error, reason} ->
        Errors.print_error(Errors.config_parse_error(path, reason))
        System.halt(1)
    end
  end

  defp run({:export, package, target, opts}) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    target_atom = String.to_atom(target)

    IO.puts("Exporting #{package} to #{target} format...")

    case Federation.check_connection_port(target_atom) do
      {:ok, info} ->
        IO.puts("  Target: #{info.command} (#{info.path})")
        if dry_run? do
          IO.puts("  [DRY RUN] Would convert and install")
        else
          IO.puts("  ⊘ Export not yet implemented")
        end
        System.halt(0)

      {:error, _reason} ->
        Errors.print_error(Errors.unknown_registry(target))
        System.halt(1)
    end
  end

  defp run({:error, message}) do
    Errors.print_error({:error, message})
    IO.puts(:stderr, "Run 'opsm help' for usage information")
    System.halt(1)
  end

  # Install helpers

  defp do_install_from_forth(forth, package, version, _allow, scope, dry_run?, _json?, native?, global?, dev?) do
    alias Opm.Package.Installer
    alias Opm.Package.Native

    forth_atom = String.to_atom(forth)
    scope_atom = String.to_atom(scope)

    if native? do
      # Use native toolchain
      IO.puts("Installing #{package}@#{version} via native @#{forth} toolchain")
      IO.puts("")

      if dry_run? do
        {cmd, args} = Native.preview_command(forth_atom, package,
          version: if(version == "latest", do: nil, else: version),
          global: global?,
          dev: dev?)
        IO.puts("[DRY RUN] Would run: #{cmd} #{Enum.join(args, " ")}")
        System.halt(0)
      else
        case Native.install(forth_atom, package,
               version: if(version == "latest", do: nil, else: version),
               global: global?,
               dev: dev?) do
          {:ok, _} ->
            IO.puts("")
            IO.puts("✓ Installed #{package} via native toolchain")
            System.halt(0)

          {:error, reason} ->
            IO.puts(:stderr, "Error: #{reason}")
            System.halt(1)
        end
      end
    else
      # Use OPM's own install (download + unpack)
      case Installer.install(forth_atom, package,
             version: version,
             scope: scope_atom,
             dry_run: dry_run?) do
        {:ok, _} ->
          System.halt(0)

        {:error, reason} ->
          IO.puts(:stderr, "Error: #{reason}")
          System.halt(1)
      end
    end
  end

  defp do_install_discover(package, version, _allow, _scope, _dry_run?, json?) do
    alias Opm.Registries.Registry

    IO.puts("Discovering: #{package}")
    IO.puts("")

    # Actually check all registries
    IO.puts("Checking registries...")
    existence = Registry.exists_all?(package)

    found_in = existence
      |> Enum.filter(fn {_, exists} -> exists end)
      |> Enum.map(fn {forth, _} -> forth end)

    if json? do
      data = %{
        package: package,
        found_in: found_in,
        availability: existence
      }
      IO.puts(Jason.encode!(data, pretty: true))
      System.halt(0)
    end

    IO.puts("")

    if found_in == [] do
      IO.puts("Package '#{package}' not found in any registry")
      IO.puts("")

      # Check for alternatives
      discovery = Federation.discover(package)
      if map_size(discovery.alternatives) > 0 do
        IO.puts("Related packages in other ecosystems:")
        for {forth, pkgs} <- discovery.alternatives, pkgs != [] do
          IO.puts("  @#{forth}: #{Enum.join(pkgs, ", ")}")
        end
      end
    else
      IO.puts("Package '#{package}' available from:")
      for forth <- found_in do
        toolchain_status = case Federation.check_toolchain(forth) do
          {:ok, %{available: tools}} -> "✓ (#{Enum.join(tools, ", ")})"
          {:ok, :no_toolchain_required} -> "✓"
          {:error, _} -> "✗ toolchain not installed"
        end
        IO.puts("  @#{forth}  #{toolchain_status}")
      end

      # Fetch and show version info for each
      IO.puts("")
      IO.puts("Latest versions:")
      for forth <- found_in do
        case Registry.fetch(forth, package) do
          {:ok, pkg} ->
            IO.puts("  @#{forth}: #{pkg.version}")
          {:error, _} ->
            :ok
        end
      end
    end

    IO.puts("")
    IO.puts("To install, specify a registry:")
    IO.puts("  opsm install @npm #{package} --version #{version}")
    IO.puts("  opsm install @cargo #{package}")
    System.halt(0)
  end
end
