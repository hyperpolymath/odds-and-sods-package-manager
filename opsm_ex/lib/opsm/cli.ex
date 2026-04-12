# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.CLI do
  @moduledoc """
  CLI entry point for OPSM - Odds-and-sods Package Manager.

  Federated package management with features from dnf, apt, nala, rpm.
  """

  require Logger

  alias Opsm.Config
  alias Opsm.Wiring
  alias Opsm.Federation
  alias Opsm.Errors
  alias Opsm.Maintenance
  alias Opsm.SmartInstall


  def main(args) do
    # Suppress noisy OTP/Bandit/Req retry logs in CLI mode — only show errors
    Logger.configure(level: :error)

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
        dev: :boolean,
        apply: :boolean,
        port: :integer,
        sustainability: :boolean,
        from: :string,
        workspace: :boolean,
        registry: :string
      ],
      aliases: [
        h: :help,
        v: :version,
        y: :yes,
        q: :quiet,
        n: :dry_run,
        g: :global,
        D: :dev,
        s: :sustainability
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
      ["api" | _] -> {:api, opts}

      # Install/Remove
      ["install" | rest] -> parse_install_args(rest, opts)

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

      # Publish/Audit (OPSM-specific)
      ["publish", path | _] -> {:publish, path, opts}
      ["publish"] -> {:error, "publish requires a path argument"}

      ["audit", package | _] -> {:audit, package, opts}
      ["audit"] -> {:error, "audit requires a package argument"}

      # Federation
      ["ports" | _] -> {:ports, opts}
      ["convert", path | _] -> {:convert, path, opts}
      ["export", package, target | _] -> {:export, package, target, opts}

      # Container commands
      ["container", "build", path | _] -> {:container_build, path, opts}
      ["container", "scan", image | _] -> {:container_scan, image, opts}
      ["container", "sign", image | _] -> {:container_sign, image, opts}
      ["container", "verify", image | _] -> {:container_verify, image, opts}
      ["container", "push", image | _] -> {:container_push, image, opts}
      ["container", "pipeline", path | _] -> {:container_pipeline, path, opts}
      ["container"] -> {:error, "container requires a subcommand (build|scan|sign|verify|push|pipeline)"}

      # Runtime management (asdf replacement)
      ["runtime", "install" | tools] -> {:runtime_install, tools, opts}
      ["runtime", "list" | _]        -> {:runtime_list, opts}
      ["runtime", "update" | tools]  -> {:runtime_update, tools, opts}
      ["runtime", "remove", tool | _] -> {:runtime_remove, tool, opts}
      ["runtime", "which", tool | _]  -> {:runtime_which, tool, opts}
      ["runtime", "current" | _]     -> {:runtime_current, opts}
      ["runtime"]                    -> {:error, "runtime requires a subcommand (install|list|update|remove|which|current)"}

      # Unknown
      [cmd | _] -> {:error, "Unknown command: #{cmd}"}
    end
  end

  defp parse_install_args([], opts) do
    cond do
      Keyword.get(opts, :workspace, false) -> {:install_workspace, opts}
      true -> {:error, "install requires a package argument"}
    end
  end

  defp parse_install_args(["@" <> forth, package | _], opts) do
    {:install, forth, package, opts}
  end

  defp parse_install_args([package], opts) do
    if String.contains?(package, ":") or String.contains?(package, "[") or String.contains?(package, "]") do
      {:smart_install, [package], opts}
    else
      {:install, nil, package, opts}
    end
  end

  defp parse_install_args(rest, opts), do: {:smart_install, rest, opts}

  defp run({:help, _opts}) do
    IO.puts("""
    opsm - Odds-and-sods Package Manager

    Federated multi-registry package manager with trust pipeline.

    USAGE:
      opsm <command> [@forth] [package] [options]

    PACKAGE COMMANDS:
      install [@forth] <pkg>   Install package (optionally from specific registry)
      install [backend:] ...   Smart install with backend grouping
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
      api                      Run local Opsm API server

    FEDERATION:
      ports                    List available system package managers
      convert <manifest>       Convert manifest (Nickel/Idris2/npm/Cargo/etc.)
      export <pkg> <target>    Export package to system format (deb/rpm/etc.)

    CONTAINER (OCI images with security):
      container build <path>   Build container image from Containerfile
      container scan <image>   Scan image for vulnerabilities (Svalinn)
      container sign <image>   Sign image with Cosign (Selur)
      container verify <image> Verify image signature (Selur)
      container push <image>   Push image to registry
      container pipeline <path> Full pipeline: build → scan → sign → push

    RUNTIME (asdf replacement — manages language toolchains):
      runtime install <tool[@ver]>  Install a runtime tool (latest if no version)
      runtime install               Install all tools pinned in [runtime] of opsm.toml
      runtime list                  List installed runtime tools and versions
      runtime update [tools...]     Update all (or specific) installed tools
      runtime remove <tool>         Remove an installed runtime tool
      runtime which <tool>          Show path to active binary for a tool
      runtime current               Show active version per tool

    OPTIONS:
      --version <ver>          Version: 1.2.3, @next, @latest, @stable
      --allow <channel>        Allow: snapshot, alpha, beta, rc, esr
      --systemwide             Install system-wide
      --user                   Install for current user (default)
      -g, --global             Global install (native mode)
      -D, --dev                Developsment dependency
      --apply                  Apply smart install plan (connection ports + select backends)
      --port                   Port for opsm api (default 4466)
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
      @go       Go modules (proxy.golang.org)
      @pub      Dart/Flutter (pub.dev)
      @hackage  Haskell (hackage.haskell.org)
      @nuget    .NET (nuget.org)
      @maven    Java/JVM (maven central)
      @nimble   Nim packages (nimble.directory)
      @idris2   Idris2 packages (curated git-based)
      @eclexia  Eclexia packages (git-based)
      @git      Any git repository
      @agentic  HAR discovery (human-assisted)

    PLANNED FORTHS (coming soon):
      @opam     OCaml (opam.ocaml.org)
      @zig      Zig packages
      @swipl    SWI-Prolog packs
      @luarocks Lua (luarocks.org)
      @cpan     Perl (metacpan.org)

    CONNECTION PORTS (system package managers):
      @deb      Debian/Ubuntu (apt)
      @rpm      Fedora/RHEL (dnf/yum)
      @rpm-ostree Fedora Silverblue (rpm-ostree)
      @dnfinition Unified OS PM bridge (dnfinition)
      @pacman   Arch Linux (pacman)
      @winget   Windows (winget)
      @choco    Windows (Chocolatey)
      @scoop    Windows (Scoop)
      @homebrew macOS/Linux (brew)
      @nix      NixOS/any (nix-env)
      @guix     Guix System (guix)
      @flatpak  Flatpak (flatpak)
      @snap     Snap (snap)

    EXAMPLES:
      opsm install lodash                      # From default/detected registry
      opsm install @npm lodash --version 4.17  # Specific version from npm
      opsm install rpm-ostree: gcc clang       # Smart install grouping
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
      opsm container build ./opsm_ex           # Build container image
      opsm container scan myapp:latest         # Scan for vulnerabilities
      opsm container pipeline ./opsm_ex        # Full security pipeline

    CONFIG:
      $OPSM_CONFIG > ./opsm.toml > ~/.config/opsm/opsm.toml
      $CONTAINER_REGISTRY > ghcr.io/hyperpolymath
      $SVALINN_URL > http://localhost:8085
      $SELUR_URL > http://localhost:8086
    """)
  end

  defp run({:status, _opts}) do
    config = Config.load_config_or_example()
    :ok = Wiring.run_status(config)
    System.halt(0)
  end

  defp run({:api, opts}) do
    port = Keyword.get(opts, :port, 4466)
    {:ok, _} = Opsm.Api.Server.start_link(port: port)
    IO.puts("OPSM API listening on http://127.0.0.1:#{port}")
    Process.sleep(:infinity)
  end

  defp run({:repolist, opts}) do
    json? = Keyword.get(opts, :json, false)

    forths = [
      %{name: "npm", url: "https://registry.npmjs.org", status: "enabled"},
      %{name: "cargo", url: "https://crates.io", status: "enabled"},
      %{name: "hex", url: "https://hex.pm", status: "enabled"},
      %{name: "pypi", url: "https://pypi.org", status: "enabled"},
      %{name: "gem", url: "https://rubygems.org", status: "enabled"},
      %{name: "go", url: "https://proxy.golang.org", status: "enabled"},
      %{name: "pub", url: "https://pub.dev", status: "enabled"},
      %{name: "hackage", url: "https://hackage.haskell.org", status: "enabled"},
      %{name: "nuget", url: "https://api.nuget.org", status: "enabled"},
      %{name: "maven", url: "https://search.maven.org", status: "enabled"},
      %{name: "nimble", url: "https://nimble.directory", status: "enabled"},
      %{name: "idris2", url: "git-based (curated list)", status: "enabled"},
      %{name: "eclexia", url: "git-based (packages.eclexia.org planned)", status: "enabled"},
      %{name: "git", url: "any git repository", status: "enabled"},
      %{name: "agentic", url: "HAR discovery queue", status: "enabled"},
      %{name: "opam", url: "https://opam.ocaml.org", status: "planned"},
      %{name: "cpan", url: "https://metacpan.org", status: "planned"},
      %{name: "luarocks", url: "https://luarocks.org", status: "planned"},
      %{name: "zig", url: "https://github.com/zigtools", status: "planned"},
      %{name: "swipl", url: "https://www.swi-prolog.org/pack/list", status: "planned"}
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

  defp run({:install_workspace, opts}) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    registry  = Keyword.get(opts, :registry)

    IO.puts("Reading workspace from opsm.toml...")

    case File.read("opsm.toml") do
      {:ok, content} ->
        members = parse_workspace_members(content)

        if members == [] do
          IO.puts("No [workspace] section or members found in opsm.toml.")
        else
          IO.puts("Workspace members: #{Enum.join(members, ", ")}")

          for member <- members do
            manifest = Path.join(member, "opsm.toml")
            if File.exists?(manifest) do
              IO.puts("\nInstalling dependencies for #{member}...")
              unless dry_run? do
                config = Config.load_config_or_example()
                forth = registry || "hf"
                case Wiring.run_publish(config, member) do
                  {:ok, _} -> IO.puts("  ✓ #{member}")
                  {:error, reason} -> IO.puts(:stderr, "  ✗ #{member}: #{reason}")
                end
                _ = forth
              end
            else
              IO.puts("  WARN: #{manifest} not found — skipping #{member}")
            end
          end
        end

      {:error, :enoent} ->
        IO.puts(:stderr, "No opsm.toml found in current directory.")
        System.halt(1)
    end

    System.halt(0)
  end

  defp run({:publish, path, opts}) do
    registry = Keyword.get(opts, :registry)
    workspace? = Keyword.get(opts, :workspace, false)

    config = Config.load_config_or_example()

    if workspace? do
      manifest = Path.join(path, "opsm.toml")
      case File.read(manifest) do
        {:ok, content} ->
          members = parse_workspace_members(content)
          if members == [] do
            IO.puts("No workspace members found in #{manifest}.")
          else
            IO.puts("Publishing workspace members to @#{registry || "hf"}...")
            for member <- members do
              member_path = Path.join(path, member)
              IO.puts("  Publishing #{member}...")
              case Wiring.run_publish(config, member_path) do
                {:ok, _} -> IO.puts("  ✓ #{member}")
                {:error, reason} ->
                  Errors.print_error({:internal, "Publish failed for #{member}: #{reason}", "Check path and credentials"})
              end
            end
          end
        {:error, :enoent} ->
          IO.puts(:stderr, "No opsm.toml found at #{manifest}")
          System.halt(1)
      end
    else
      case Wiring.run_publish(config, path) do
        {:ok, _} -> :ok
        {:error, reason} ->
          Errors.print_error({:internal, "Publish failed: #{reason}", "Check path and credentials"})
          System.halt(1)
      end
    end

    System.halt(0)
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
    sustainability? = Keyword.get(opts, :sustainability, false)
    scope = cond do
      Keyword.get(opts, :systemwide) -> "systemwide"
      true -> "user"
    end

    if dry_run?, do: IO.puts("[DRY RUN]")
    if sustainability?, do: IO.puts("[SUSTAINABILITY] Preferring packages with higher sustainability scores")

    if forth do
      # Specific registry requested
      do_install_from_forth(forth, package, version, allow, scope, dry_run?, json?, native?, global?, dev?, sustainability?)
    else
      # No registry specified - discover across all
      do_install_discover(package, version, allow, scope, dry_run?, json?, sustainability?)
    end
  end

  defp run({:smart_install, rest, opts}) do
    plan = SmartInstall.parse(rest)
    print_smart_plan(plan)

    if opts[:apply] do
      scope =
        cond do
          Keyword.get(opts, :systemwide) -> :system
          true -> :user
        end

      results =
        SmartInstall.execute(plan,
          dry_run: Keyword.get(opts, :dry_run, false),
          scope: scope,
          native: Keyword.get(opts, :native, false),
          global: Keyword.get(opts, :global, false),
          dev: Keyword.get(opts, :dev, false),
          sustainability_preference: Keyword.get(opts, :sustainability, false)
        )

      print_smart_results(results)
    else
      IO.puts("Dry-run only. Use --apply to execute when available.")
    end
  end

  defp run({:remove, package, opts}) do
    alias Opsm.Package.Installer

    dry_run? = Keyword.get(opts, :dry_run, false)

    case Installer.remove(package, dry_run: dry_run?) do
      :ok -> System.halt(0)
      {:ok, :dry_run} -> System.halt(0)
      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end

  defp run({:reinstall, package, opts}) do
    alias Opsm.Lockfile
    alias Opsm.Package.Installer

    dry_run? = Keyword.get(opts, :dry_run, false)

    IO.puts("Reinstalling: #{package}")

    # Look up the package in the lockfile to get its forth and version
    case Lockfile.read() do
      {:ok, lockfile} ->
        # Find the package across any forth
        entries = Lockfile.list_packages(lockfile)
          |> Enum.filter(fn p -> p.name == package end)

        case entries do
          [] ->
            IO.puts(:stderr, "Error: #{package} is not installed (not in lockfile)")
            System.halt(1)

          [entry | _] ->
            forth = entry.forth
            version = entry.version
            IO.puts("  Found #{package}@#{version} from @#{forth}")

            # Remove then reinstall
            if dry_run? do
              IO.puts("[DRY RUN] Would remove #{package}")
              IO.puts("[DRY RUN] Would install #{package}@#{version} from @#{forth}")
            else
              IO.puts("  Removing...")
              _ = Installer.remove(package, dry_run: false)
              IO.puts("  Installing #{package}@#{version}...")
              case do_install_from_forth(forth, package, version, nil, "user", false, false, false, false, false) do
                _ -> :ok
              end
            end
            System.halt(0)
        end

      {:error, :not_found} ->
        IO.puts(:stderr, "Error: No lockfile found. Cannot determine installed packages.")
        System.halt(1)

      {:error, reason} ->
        IO.puts(:stderr, "Error reading lockfile: #{reason}")
        System.halt(1)
    end
  end

  defp run({:update, packages, opts}) do
    alias Opsm.Lockfile
    alias Opsm.Registries.Registry

    dry_run? = Keyword.get(opts, :dry_run, false)
    if dry_run?, do: IO.puts("[DRY RUN]")

    case Lockfile.read() do
      {:ok, lockfile} ->
        entries = Lockfile.list_packages(lockfile)

        # Filter to requested packages or all
        targets = if packages == [] do
          IO.puts("Checking all #{length(entries)} installed packages for updates...")
          entries
        else
          IO.puts("Checking: #{Enum.join(packages, ", ")}")
          Enum.filter(entries, fn p -> p.name in packages end)
        end

        updates = targets
          |> Enum.map(fn entry ->
            case Registry.fetch(entry.forth, entry.name) do
              {:ok, latest} ->
                if latest.version != entry.version do
                  {entry, latest.version}
                else
                  nil
                end
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if updates == [] do
          IO.puts("\n✓ All packages are up to date")
        else
          IO.puts("\n#{length(updates)} update(s) available:\n")
          for {entry, new_version} <- updates do
            IO.puts("  #{entry.name}: #{entry.version} → #{new_version} (@#{entry.forth})")
          end

          unless dry_run? do
            IO.puts("\nInstalling updates...")
            for {entry, new_version} <- updates do
              IO.puts("  Updating #{entry.name} to #{new_version}...")
              do_install_from_forth(entry.forth, entry.name, new_version, nil, "user", false, false, false, false, false)
            end
            IO.puts("\n✓ #{length(updates)} package(s) updated")
          end
        end
        System.halt(0)

      {:error, :not_found} ->
        IO.puts("No lockfile found. Nothing to update.")
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error reading lockfile: #{reason}")
        System.halt(1)
    end
  end

  defp run({:check_update, opts}) do
    alias Opsm.Lockfile
    alias Opsm.Registries.Registry

    json? = Keyword.get(opts, :json, false)

    case Lockfile.read() do
      {:ok, lockfile} ->
        entries = Lockfile.list_packages(lockfile)
        IO.puts("Checking #{length(entries)} installed package(s) for updates...\n")

        updates = entries
          |> Enum.map(fn entry ->
            case Registry.fetch(entry.forth, entry.name) do
              {:ok, latest} ->
                if latest.version != entry.version do
                  %{name: entry.name, current: entry.version, latest: latest.version, forth: entry.forth}
                else
                  nil
                end
              _ -> nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        if json? do
          IO.puts(Jason.encode!(updates, pretty: true))
        else
          if updates == [] do
            IO.puts("✓ All packages are up to date")
          else
            IO.puts("#{length(updates)} update(s) available:\n")
            # Column-aligned output
            max_name = updates |> Enum.map(fn u -> String.length(u.name) end) |> Enum.max()
            max_cur = updates |> Enum.map(fn u -> String.length(u.current) end) |> Enum.max()

            for u <- updates do
              name_pad = String.pad_trailing(u.name, max_name)
              cur_pad = String.pad_trailing(u.current, max_cur)
              IO.puts("  #{name_pad}  #{cur_pad} → #{u.latest}  (@#{u.forth})")
            end

            IO.puts("\nRun `opsm update` to install all updates")
          end
        end
        System.halt(0)

      {:error, :not_found} ->
        IO.puts("No lockfile found. Install packages first.")
        System.halt(0)

      {:error, reason} ->
        IO.puts(:stderr, "Error reading lockfile: #{reason}")
        System.halt(1)
    end
  end

  defp run({:search, query, opts}) do
    alias Opsm.Registries.Registry

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
    alias Opsm.Registries.Registry

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
    alias Opsm.Package.Installer

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
          forth = Opsm.Validation.safe_to_forth(pkg["forth"])
          case Opsm.Registries.Registry.fetch(forth, pkg["name"]) do
            {:ok, latest} ->
              if latest.version != pkg["version"] do
                IO.puts("  #{pkg["name"]}: #{pkg["version"]} -> #{latest.version}")
              end
            _ -> :ok
          end
        end

      :available ->
        IO.puts("Available package registries:")
        IO.puts("")
        forths = [:npm, :hex, :cargo, :pypi, :nimble, :idris2, :eclexia, :git, :agentic]
        for forth <- forths do
          IO.puts("  @#{forth}")
        end
        IO.puts("")
        IO.puts("Use `opsm search <query>` to find packages across all registries")

      :obsoletes ->
        IO.puts("Checking for obsolete packages...")
        installed = Installer.list_installed()

        if installed == [] do
          IO.puts("No packages installed")
        else
          obsolete = Enum.filter(installed, fn pkg ->
            forth = Opsm.Validation.safe_to_forth(pkg["forth"])
            case Opsm.Registries.Registry.exists?(forth, pkg["name"]) do
              false -> true
              _ -> false
            end
          end)

          if obsolete == [] do
            IO.puts("No obsolete packages found")
          else
            IO.puts("#{length(obsolete)} obsolete package(s) (no longer in registry):\n")
            for pkg <- obsolete do
              IO.puts("  #{pkg["name"]}@#{pkg["version"]} (@#{pkg["forth"]})")
            end
          end
        end
    end

    System.halt(0)
  end

  defp run({:provides, file, opts}) do
    alias Opsm.Lockfile
    json? = Keyword.get(opts, :json, false)

    IO.puts("Finding package that provides: #{file}\n")

    # Check installed packages first
    providers = case Lockfile.read() do
      {:ok, lockfile} ->
        install_dir = Path.expand("~/.local/share/opsm/packages")
        Lockfile.list_packages(lockfile)
        |> Enum.filter(fn entry ->
          pkg_dir = Path.join(install_dir, "#{entry.name}-#{entry.version}")
          if File.dir?(pkg_dir) do
            # Search for matching file in installed package
            case File.ls(pkg_dir) do
              {:ok, files} ->
                Enum.any?(files, fn f ->
                  String.contains?(f, file) or f == file
                end)
              _ -> false
            end
          else
            false
          end
        end)
        |> Enum.map(fn entry ->
          %{name: entry.name, version: entry.version, forth: entry.forth, source: "installed"}
        end)
      _ -> []
    end

    # Also search across registries by name (the file might be the package name)
    registry_matches = case Opsm.Registries.Registry.search_all(file, limit: 5) do
      results when is_map(results) ->
        results
        |> Enum.flat_map(fn {forth, pkgs} ->
          case pkgs do
            list when is_list(list) ->
              Enum.map(list, fn p -> Map.put(p, :forth, forth) |> Map.put(:source, "registry") end)
            _ -> []
          end
        end)
        |> Enum.take(10)
      _ -> []
    end

    all_results = providers ++ registry_matches

    if json? do
      IO.puts(Jason.encode!(all_results, pretty: true))
    else
      if providers != [] do
        IO.puts("Installed packages providing '#{file}':")
        for p <- providers do
          IO.puts("  #{p.name}@#{p.version} (@#{p.forth})")
        end
        IO.puts("")
      end

      if registry_matches != [] do
        IO.puts("Registry packages matching '#{file}':")
        for p <- registry_matches do
          IO.puts("  #{p[:name]} #{p[:version] || ""} (@#{p[:forth]})")
        end
      end

      if all_results == [] do
        IO.puts("No packages found providing '#{file}'")
      end
    end
    System.halt(0)
  end

  defp run({:depends, package, opts}) do
    alias Opsm.Resolver
    alias Opsm.Lockfile

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
    alias Opsm.Lockfile
    alias Opsm.Colour

    json? = Keyword.get(opts, :json, false)

    IO.puts("Reverse dependencies for: #{Colour.cyan(package)}")
    IO.puts("")

    case Lockfile.read() do
      {:ok, lockfile} ->
        # Find packages that depend on this one
        dependents =
          Lockfile.list_packages(lockfile)
          |> Enum.filter(fn pkg ->
            deps = pkg.dependencies || []
            # Handle both string lists and map-keyed dependencies
            cond do
              is_list(deps) -> Enum.member?(deps, package)
              is_map(deps) -> Map.has_key?(deps, package)
              true -> false
            end
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
            IO.puts("Packages that depend on #{Colour.cyan(package)}:")
            Enum.each(dependents, fn pkg ->
              IO.puts("  - #{Colour.cyan("#{pkg.name}")}@#{pkg.version}")
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

      "clear" ->
        IO.puts("Clearing history...")
        File.rm(Path.expand("~/.local/share/opsm/history.json"))
        IO.puts("✓ History cleared")
        System.halt(0)

      "redo" ->
        case Maintenance.redo_last() do
          {:ok, _, _} -> System.halt(0)
          {:error, reason} ->
            Errors.print_error({:error, reason})
            System.halt(1)
        end

      _ ->
        IO.puts("Unknown history action: #{action}")
        IO.puts("Available: list, undo, redo, info, clear")
        System.halt(1)
    end
  end

  defp run({:download, package, _opts}) do
    alias Opsm.Registries.Registry
    alias Opsm.Package.Downloader

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

  defp run({:check, opts}) do
    alias Opsm.Lockfile
    alias Opsm.Package.{Installer, Downloader}

    json? = Keyword.get(opts, :json, false)

    IO.puts("Verifying package integrity...\n")

    # 1. Verify lockfile integrity (SHA3-512 tamper detection)
    case Lockfile.read() do
      {:ok, lockfile} ->
        case Lockfile.verify_integrity(lockfile) do
          :ok ->
            IO.puts("✓ Lockfile integrity: SHA3-512 hash verified")
          {:ok, :no_integrity_hash} ->
            IO.puts("⚠ Lockfile integrity: No integrity hash (legacy lockfile)")
          {:error, reason} ->
            IO.puts("✗ Lockfile integrity: #{reason}")
        end
      {:error, _} ->
        IO.puts("⚠ No lockfile found")
    end

    IO.puts("")

    # 2. Verify installed packages against their recorded checksums
    installed = Installer.list_installed()

    results = Enum.map(installed, fn pkg ->
      name = pkg["name"]
      version = pkg["version"]
      forth = pkg["forth"]
      path = pkg["path"]
      recorded_checksum = pkg["checksum"]

      dir_exists = File.dir?(path)

      # Try to recompute checksum from cached tarball
      checksum_status = cond do
        not dir_exists ->
          :missing

        is_nil(recorded_checksum) or recorded_checksum == "" ->
          :no_checksum

        true ->
          # Find cached tarball and recompute
          cache_dir = Path.expand("~/.cache/opsm/packages")
          cache_pattern = Path.join([cache_dir, forth, "#{name}-#{version}*"])

          cached_files = Path.wildcard(cache_pattern)
          case cached_files do
            [cached_tarball | _] ->
              recomputed = Downloader.compute_file_checksum(cached_tarball, :sha256)
              # Check against SHA256 first, then SHA1 (npm uses SHA1)
              if recomputed == recorded_checksum do
                :verified
              else
                sha1 = Downloader.compute_file_checksum(cached_tarball, :sha1)
                if sha1 == recorded_checksum do
                  :verified
                else
                  :tampered
                end
              end

            [] ->
              # No cached tarball — can't verify, but files exist
              :cache_missing
          end
      end

      %{
        name: name,
        version: version,
        forth: forth,
        path: path,
        installed: dir_exists,
        checksum_status: checksum_status
      }
    end)

    if json? do
      IO.puts(Jason.encode!(results, pretty: true))
    else
      missing = Enum.filter(results, fn r -> not r.installed end)
      verified = Enum.filter(results, fn r -> r.checksum_status == :verified end)
      no_checksum = Enum.filter(results, fn r -> r.checksum_status == :no_checksum end)
      tampered = Enum.filter(results, fn r -> r.checksum_status == :tampered end)
      cache_missing = Enum.filter(results, fn r -> r.checksum_status == :cache_missing end)

      IO.puts("Package verification (#{length(installed)} installed):\n")

      if verified != [] do
        IO.puts("  ✓ #{length(verified)} verified (checksum match)")
      end

      if cache_missing != [] do
        IO.puts("  ⚠ #{length(cache_missing)} not verifiable (cached tarball cleaned):")
        for r <- cache_missing do
          IO.puts("    - #{r.name}@#{r.version}")
        end
      end

      if no_checksum != [] do
        IO.puts("  ⚠ #{length(no_checksum)} without checksums:")
        for r <- no_checksum do
          IO.puts("    - #{r.name}@#{r.version}")
        end
      end

      if tampered != [] do
        IO.puts("  ✗ #{length(tampered)} CHECKSUM MISMATCH:")
        for r <- tampered do
          IO.puts("    - #{r.name}@#{r.version} — REINSTALL RECOMMENDED")
        end
      end

      if missing != [] do
        IO.puts("  ✗ #{length(missing)} missing from disk:")
        for r <- missing do
          IO.puts("    - #{r.name}@#{r.version}")
        end
      end

      if tampered == [] and missing == [] do
        IO.puts("\n✓ All packages OK")
      end
    end

    System.halt(if(Enum.any?(results, fn r -> r.checksum_status == :tampered end), do: 1, else: 0))
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
    target_atom = Opsm.Validation.safe_to_target(target)

    IO.puts("Exporting #{package} to #{target} format...")

    case Federation.check_connection_port(target_atom) do
      {:ok, info} ->
        IO.puts("  Target: #{info.command} (#{info.path})")

        # Try to find the package in lockfile first, then resolve it
        pkg = case Opsm.Lockfile.read() do
          {:ok, lockfile} ->
            entries = Opsm.Lockfile.list_packages(lockfile)
              |> Enum.filter(fn p -> p.name == package end)
            case entries do
              [entry | _] ->
                case Opsm.Registries.Registry.fetch(entry.forth, entry.name, entry.version) do
                  {:ok, resolved} -> resolved
                  _ -> nil
                end
              _ -> nil
            end
          _ -> nil
        end

        if pkg do
          if dry_run? do
            IO.puts("  [DRY RUN] Would export #{pkg.package}@#{pkg.version} to #{target}")
            IO.puts("  [DRY RUN] Would run: #{info.command} install #{package}")
          else
            IO.puts("  Installing #{package} via #{info.command}...")
            case Federation.install_via_port(package, target_atom) do
              {:ok, output} ->
                IO.puts("  ✓ Exported and installed via #{info.command}")
                if is_binary(output) and output != "", do: IO.puts("  #{output}")
              {:error, reason} ->
                IO.puts(:stderr, "  Error: #{reason}")
                System.halt(1)
            end
          end
        else
          # Package not in lockfile, try direct install via connection port
          if dry_run? do
            IO.puts("  [DRY RUN] Would install #{package} via #{info.command}")
          else
            IO.puts("  Installing #{package} via #{info.command}...")
            case Federation.install_via_port(package, target_atom) do
              {:ok, output} ->
                IO.puts("  ✓ Installed via #{info.command}")
                if is_binary(output) and output != "", do: IO.puts("  #{output}")
              {:error, reason} ->
                IO.puts(:stderr, "  Error: #{reason}")
                System.halt(1)
            end
          end
        end
        System.halt(0)

      {:error, _reason} ->
        Errors.print_error(Errors.unknown_registry(target))
        System.halt(1)
    end
  end

  defp run({:container_build, path, opts}) do
    tag = Keyword.get(opts, :version, "latest")

    IO.puts("Building container image from: #{path}")

    case Opsm.Container.build(path, tag: tag) do
      {:ok, image} ->
        IO.puts("✓ Built: #{image.tag}")
        if image.digest, do: IO.puts("  Digest: #{image.digest}")
        System.halt(0)

      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:container_scan, image, _opts}) do
    svalinn_url = System.get_env("SVALINN_URL", "http://localhost:8085")

    IO.puts("Scanning container image: #{image}")

    case Opsm.Container.scan(image, svalinn_url) do
      {:ok, result} ->
        IO.puts("✓ Scan complete")
        IO.puts("  Critical: #{result.critical}")
        IO.puts("  High: #{result.high}")
        IO.puts("  Medium: #{result.medium}")
        IO.puts("  Low: #{result.low}")
        System.halt(0)

      {:error, result} when is_struct(result, Opsm.Types.ScanResult) ->
        IO.puts("✗ Security vulnerabilities found")
        IO.puts("  Critical: #{result.critical}")
        IO.puts("  High: #{result.high}")
        Errors.print_error({:error, "Image has critical vulnerabilities"})
        System.halt(1)

      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:container_sign, image, _opts}) do
    selur_url = System.get_env("SELUR_URL", "http://localhost:8086")
    key_path = System.get_env("SIGNING_KEY", "/keys/signing.key")

    IO.puts("Signing container image: #{image}")

    case Opsm.Container.sign(image, selur_url, key_path) do
      {:ok, result} ->
        IO.puts("✓ Image signed successfully")
        IO.puts("  Algorithm: #{result.algorithm}")
        System.halt(0)

      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:container_verify, image, _opts}) do
    selur_url = System.get_env("SELUR_URL", "http://localhost:8086")
    pubkey_path = System.get_env("VERIFY_KEY", "/keys/signing.pub")

    IO.puts("Verifying container image: #{image}")

    case Opsm.Container.verify(image, selur_url, pubkey_path) do
      {:ok, :verified} ->
        IO.puts("✓ Signature verified")
        System.halt(0)

      {:error, :verification_failed} ->
        Errors.print_error({:error, "Signature verification failed"})
        System.halt(1)

      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:container_push, image, _opts}) do
    registry = System.get_env("CONTAINER_REGISTRY", "ghcr.io/hyperpolymath")

    IO.puts("Pushing container image: #{image}")

    case Opsm.Container.push(image, registry) do
      {:ok, pushed_image} ->
        IO.puts("✓ Image pushed: #{pushed_image}")
        System.halt(0)

      {:error, reason} ->
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:container_pipeline, path, opts}) do
    tag = Keyword.get(opts, :version, "latest")
    registry = System.get_env("CONTAINER_REGISTRY", "ghcr.io/hyperpolymath")
    svalinn_url = System.get_env("SVALINN_URL", "http://localhost:8085")
    selur_url = System.get_env("SELUR_URL", "http://localhost:8086")
    key_path = System.get_env("SIGNING_KEY", "/keys/signing.key")

    IO.puts("Starting container security pipeline")
    IO.puts("")

    case Opsm.Container.publish_pipeline(path, registry,
           tag: tag,
           svalinn_url: svalinn_url,
           selur_url: selur_url,
           key_path: key_path
         ) do
      {:ok, result} ->
        IO.puts("")
        IO.puts("✓ Pipeline completed successfully")
        IO.puts("  Image: #{result.image}")
        if result.digest, do: IO.puts("  Digest: #{result.digest}")
        System.halt(0)

      {:error, reason} ->
        IO.puts("")
        Errors.print_error({:error, reason})
        System.halt(1)
    end
  end

  defp run({:error, message}) do
    Errors.print_error({:error, message})
    IO.puts(:stderr, "Run 'opsm help' for usage information")
    System.halt(1)
  end

  # Helper functions

  defp show_dependencies_from_lockfile(lockfile, package, recursive?, json?) do
    case Opsm.Lockfile.packages_for_name(lockfile, package) do
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
          case Opsm.Lockfile.packages_for_name(lockfile, pkg_name) do
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

  # Install helpers

  defp do_install_from_forth(forth, package, version, _allow, scope, dry_run?, _json?, native?, global?, dev?, sustainability? \\ false) do
    alias Opsm.Package.Installer
    alias Opsm.Package.Native

    forth_atom = Opsm.Validation.safe_to_forth(forth)
    scope_atom = Opsm.Validation.safe_to_scope(scope)

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
      # Use OPSM's own install (download + unpack)
      case Installer.install(forth_atom, package,
             version: version,
             scope: scope_atom,
             dry_run: dry_run?,
             sustainability_preference: sustainability?) do
        {:ok, _} ->
          System.halt(0)

        {:error, reason} ->
          IO.puts(:stderr, "Error: #{reason}")
          System.halt(1)
      end
    end
  end

  defp do_install_discover(package, version, allow, scope, dry_run?, json?, sustainability?) do
    alias Opsm.Registries.Registry

    IO.puts("Discovering: #{package}")
    IO.puts("")

    # Check all registries in parallel
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

    cond do
      found_in == [] ->
        # Not found anywhere
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
        System.halt(1)

      length(found_in) == 1 ->
        # Found in exactly one registry — install directly
        [forth] = found_in
        IO.puts("Found in @#{forth}")
        IO.puts("")
        do_install_from_forth(to_string(forth), package, version, allow, scope, dry_run?, false, false, false, false, sustainability?)

      true ->
        # Found in multiple registries — show options and auto-select best
        IO.puts("Package '#{package}' available from:")
        registry_info = for forth <- found_in do
          toolchain_ok = case Federation.check_toolchain(forth) do
            {:ok, _} -> true
            {:error, _} -> false
          end
          pkg_version = try do
            case Registry.fetch(forth, package) do
              {:ok, pkg} -> pkg.version
              _ -> "unknown"
            end
          rescue
            _ -> "unknown"
          end
          IO.puts("  @#{forth}  v#{pkg_version}  #{if toolchain_ok, do: "✓ toolchain ready", else: "✗ toolchain missing"}")
          {forth, toolchain_ok, pkg_version}
        end

        # Auto-select: prefer primary registries with toolchains, then by highest version
        # Primary registries are the canonical homes — npm for JS, cargo for Rust, etc.
        primary_forths = [:npm, :cargo, :hex, :pypi, :gem, :go, :pub, :hackage, :nuget, :maven]

        selected = registry_info
        |> Enum.filter(fn {_forth, toolchain_ok, _v} -> toolchain_ok end)
        |> case do
          [] -> registry_info
          with_toolchain -> with_toolchain
        end
        |> Enum.sort_by(fn {forth, _ok, version} ->
          primary_rank = case Enum.find_index(primary_forths, &(&1 == forth)) do
            nil -> 100
            idx -> idx
          end
          # Prefer primary registries, then highest version
          {primary_rank, version}
        end)
        |> List.first()

        case selected do
          {forth, _ok, _v} ->
            IO.puts("")
            IO.puts("Auto-selected: @#{forth}")
            IO.puts("")
            do_install_from_forth(to_string(forth), package, version, allow, scope, dry_run?, false, false, false, false, sustainability?)

          nil ->
            IO.puts("")
            IO.puts("Could not auto-select a registry. Specify one:")
            for forth <- found_in do
              IO.puts("  opsm install @#{forth} #{package}")
            end
            System.halt(1)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Runtime management handlers (asdf replacement)
  # ---------------------------------------------------------------------------

  defp run({:runtime_list, opts}) do
    alias Opsm.Runtime.Manager

    json? = Keyword.get(opts, :json, false)
    installed = Manager.list_installed()

    if json? do
      IO.puts(Jason.encode!(installed, pretty: true))
    else
      if installed == [] do
        IO.puts("No runtime tools installed via OPSM.")
        IO.puts("Use 'opsm runtime install <tool>@<version>' to install.")
      else
        IO.puts("Installed runtime tools")
        IO.puts("=======================")
        max_name = installed |> Enum.map(fn t -> String.length(t.name) end) |> Enum.max(fn -> 4 end)

        for tool <- installed do
          name_pad = String.pad_trailing(tool.name, max_name)
          active_marker = if Map.get(tool, :active, false), do: " *", else: "  "
          IO.puts("#{active_marker} #{name_pad}  #{tool.version}")
        end

        IO.puts("")
        IO.puts("(* = active version)")
      end
    end

    System.halt(0)
  end

  defp run({:runtime_update, [], opts}) do
    # Update all installed tools
    alias Opsm.Runtime.Manager

    dry_run? = Keyword.get(opts, :dry_run, false)
    IO.puts("Checking for runtime tool updates...")

    case Manager.check_updates() do
      {:ok, []} ->
        IO.puts("All runtime tools are up to date.")

      {:ok, updates} ->
        IO.puts("#{length(updates)} update(s) available:\n")
        max_name = updates |> Enum.map(fn u -> String.length(u.name) end) |> Enum.max(fn -> 4 end)
        max_cur = updates |> Enum.map(fn u -> String.length(u.current) end) |> Enum.max(fn -> 7 end)

        for u <- updates do
          name_pad = String.pad_trailing(u.name, max_name)
          cur_pad  = String.pad_trailing(u.current, max_cur)
          IO.puts("  #{name_pad}  #{cur_pad} → #{u.latest}")
        end

        unless dry_run? do
          IO.puts("")
          IO.puts("Updating...")
          for u <- updates do
            case Manager.install(u.name, u.latest) do
              :ok ->
                IO.puts("  ✓ #{u.name} #{u.current} → #{u.latest}")
              {:error, reason} ->
                IO.puts(:stderr, "  ✗ #{u.name}: #{inspect(reason)}")
            end
          end
        end
    end

    System.halt(0)
  end

  defp run({:runtime_update, tools, opts}) do
    # Update specific tools
    alias Opsm.Runtime.Manager

    dry_run? = Keyword.get(opts, :dry_run, false)

    for tool_spec <- tools do
      {tool, _version} = parse_tool_spec(tool_spec)
      IO.puts("Checking updates for #{tool}...")

      case Manager.latest_version(tool) do
        {:ok, latest} ->
          current = Manager.current_version(tool)
          if current == latest do
            IO.puts("  #{tool} is already at #{latest}")
          else
            IO.puts("  #{tool}: #{current} → #{latest}")
            unless dry_run? do
              case Manager.install(tool, latest) do
                :ok ->
                  IO.puts("  ✓ Updated #{tool} to #{latest}")
                {:error, reason} ->
                  IO.puts(:stderr, "  ✗ #{tool}: #{inspect(reason)}")
              end
            end
          end

        {:error, :not_installed} ->
          IO.puts("  #{tool} is not installed. Use: opsm runtime install #{tool}")

        {:error, reason} ->
          IO.puts(:stderr, "  Error: #{inspect(reason)}")
      end
    end

    System.halt(0)
  end

  defp run({:runtime_install, [], opts}) do
    # Install from [runtime] section of opsm.toml
    alias Opsm.Runtime.Manager

    from = Keyword.get(opts, :from, "opsm.toml")
    dry_run? = Keyword.get(opts, :dry_run, false)
    IO.puts("Reading runtime pins from #{from}...")

    case Manager.install_from_manifest(from) do
      {:ok, tools} when tools == [] ->
        IO.puts("No [runtime] section found in #{from}.")

      {:ok, tools} ->
        IO.puts("Installing #{length(tools)} pinned runtime tool(s)...")
        for {tool, version} <- tools do
          IO.puts("  #{tool}@#{version}")
          unless dry_run? do
            case Manager.install(tool, version) do
              :ok -> IO.puts("  ✓ #{tool}@#{version}")
              {:error, reason} -> IO.puts(:stderr, "  ✗ #{tool}@#{version}: #{inspect(reason)}")
            end
          end
        end

      {:error, reason} ->
        IO.puts(:stderr, "Error reading #{from}: #{inspect(reason)}")
        System.halt(1)
    end

    System.halt(0)
  end

  defp run({:runtime_install, tool_specs, opts}) do
    alias Opsm.Runtime.Manager

    dry_run? = Keyword.get(opts, :dry_run, false)

    for spec <- tool_specs do
      {tool, version} = parse_tool_spec(spec)
      resolved_version = if version == "latest" do
        case Manager.latest_version(tool) do
          {:ok, v} -> v
          {:error, _} -> "latest"
        end
      else
        version
      end

      IO.puts("Installing #{tool}@#{resolved_version}...")

      unless dry_run? do
        case Manager.install(tool, resolved_version) do
          :ok ->
            IO.puts("✓ Installed #{tool}@#{resolved_version}")
            IO.puts("  Run: opsm runtime which #{tool}")
          {:error, {:missing_system_dependencies, deps}} ->
            IO.puts(:stderr, "✗ #{tool}: missing system dependencies: #{Enum.join(deps, ", ")}")
            System.halt(1)
          {:error, reason} ->
            IO.puts(:stderr, "✗ #{tool}: #{inspect(reason)}")
            System.halt(1)
        end
      end
    end

    System.halt(0)
  end

  defp run({:runtime_remove, tool, _opts}) do
    alias Opsm.Runtime.Manager

    IO.puts("Removing runtime tool: #{tool}")

    case Manager.remove(tool) do
      :ok ->
        IO.puts("✓ Removed #{tool}")
      {:error, :not_installed} ->
        IO.puts("#{tool} is not installed")
      {:error, reason} ->
        IO.puts(:stderr, "Error removing #{tool}: #{inspect(reason)}")
        System.halt(1)
    end

    System.halt(0)
  end

  defp run({:runtime_which, tool, _opts}) do
    alias Opsm.Runtime.Manager

    case Manager.which(tool) do
      {:ok, path} ->
        IO.puts(path)
      {:error, :not_installed} ->
        IO.puts(:stderr, "#{tool} is not managed by OPSM runtime")
        System.halt(1)
    end

    System.halt(0)
  end

  defp run({:runtime_current, opts}) do
    alias Opsm.Runtime.Manager

    json? = Keyword.get(opts, :json, false)
    current = Manager.list_active()

    if json? do
      IO.puts(Jason.encode!(current, pretty: true))
    else
      if current == [] do
        IO.puts("No active runtime tools.")
      else
        IO.puts("Active runtime tools")
        IO.puts("====================")
        for {tool, version} <- current do
          IO.puts("  #{tool}  #{version}")
        end
      end
    end

    System.halt(0)
  end

  # Parse the [workspace] members list from an opsm.toml content string.
  # Returns ["member1", "member2", ...] from the `members = [...]` array.
  defp parse_workspace_members(content) do
    content
    |> String.split("\n")
    |> Enum.reduce({false, []}, fn line, {in_ws, acc} ->
      stripped = String.trim(line)
      cond do
        stripped == "[workspace]" -> {true, acc}
        String.starts_with?(stripped, "[") and stripped != "[workspace]" and in_ws -> {false, acc}
        in_ws and String.starts_with?(stripped, "members") ->
          # members = ["a", "b", "c"] — extract the values
          values =
            Regex.scan(~r/"([^"]+)"/, stripped)
            |> Enum.map(fn [_, m] -> m end)
          {true, acc ++ values}
        true -> {in_ws, acc}
      end
    end)
    |> elem(1)
  end

  # Parse "tool@version" or just "tool" (defaulting to "latest")
  defp parse_tool_spec(spec) do
    case String.split(spec, "@", parts: 2) do
      [tool, version] -> {tool, version}
      [tool]          -> {tool, "latest"}
    end
  end

  defp print_smart_plan(plan) do
    IO.puts("Smart install plan (grouped by backend):")
    Enum.each(plan, fn {backend, pkgs} ->
      status =
        case SmartInstall.backend_availability(backend) do
          {:ok, _} -> "✓"
          {:error, reason} -> "✗ #{reason}"
        end

      IO.puts("  - #{backend}: #{Enum.join(pkgs, ", ")}  [#{status}]")
    end)
  end

  defp print_smart_results(results) do
    Enum.each(results, fn {backend, entries} ->
      Enum.each(entries, fn
        {:dry_run, pkg, cmd} ->
          IO.puts("[DRY RUN] #{backend}: #{pkg} -> #{cmd}")

        {:ok, pkg, message} ->
          IO.puts("✓ #{backend}: #{pkg} -> #{message}")

        {:error, pkg, reason} ->
          Errors.print_error({:error, "#{backend}: #{pkg} failed: #{reason}"})
      end)
    end)
  end
end
