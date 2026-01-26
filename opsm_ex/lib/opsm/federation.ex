# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Federation do
  @moduledoc """
  Federation layer for multi-source package resolution.

  Supports three federation modes:
  1. Manifest conversion - Generic Idris2/Nickel manifest translation
  2. Agentic fetch - Direct fetch via agent (LLM-assisted discovery)
  3. Connection port - Bridge to system package managers (deb/rpm/winget/choco/scoop)
  """

  alias Opsm.Types.{
    ForthConfig,
    ManifestFormat,
    InstallRequest,
    ResolvedPackage,
    ConnectionPort
  }

  # =============================================================================
  # Default Forth Configurations
  # =============================================================================

  @default_forths [
    # Language ecosystems (direct API)
    %ForthConfig{
      name: :npm,
      forth_type: :npm,
      base_url: "https://registry.npmjs.org",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :cargo,
      forth_type: :cargo,
      base_url: "https://crates.io/api/v1",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :hex,
      forth_type: :hex,
      base_url: "https://hex.pm/api",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :pypi,
      forth_type: :pypi,
      base_url: "https://pypi.org/pypi",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :gem,
      forth_type: :gem,
      base_url: "https://rubygems.org/api/v1",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :nuget,
      forth_type: :nuget,
      base_url: "https://api.nuget.org/v3",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :maven,
      forth_type: :maven,
      base_url: "https://repo1.maven.org/maven2",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :pub,
      forth_type: :pub,
      base_url: "https://pub.dev/api",
      federation_mode: :manifest_convert
    },
    %ForthConfig{
      name: :go,
      forth_type: :go,
      base_url: "https://proxy.golang.org",
      federation_mode: :manifest_convert
    },
    # System package managers (connection port)
    %ForthConfig{
      name: :deb,
      forth_type: :deb,
      base_url: "local://apt",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :rpm,
      forth_type: :rpm,
      base_url: "local://dnf",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :winget,
      forth_type: :winget,
      base_url: "local://winget",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :choco,
      forth_type: :choco,
      base_url: "local://choco",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :scoop,
      forth_type: :scoop,
      base_url: "local://scoop",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :pacman,
      forth_type: :pacman,
      base_url: "local://pacman",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :homebrew,
      forth_type: :homebrew,
      base_url: "https://formulae.brew.sh/api",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :nix,
      forth_type: :nix,
      base_url: "https://search.nixos.org/packages",
      federation_mode: :connection_port,
      enabled: false
    },
    %ForthConfig{
      name: :guix,
      forth_type: :guix,
      base_url: "https://packages.guix.gnu.org",
      federation_mode: :connection_port,
      enabled: false
    }
  ]

  @doc """
  Get all configured forths.
  """
  def list_forths do
    @default_forths
  end

  @doc """
  Get enabled forths only.
  """
  def enabled_forths do
    Enum.filter(@default_forths, & &1.enabled)
  end

  @doc """
  Find forth config by name.
  """
  def get_forth(name) when is_atom(name) do
    Enum.find(@default_forths, fn f -> f.name == name end)
  end

  def get_forth(name) when is_binary(name) do
    get_forth(String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  # =============================================================================
  # Mode 1: Manifest Conversion (Nickel/Idris2)
  # =============================================================================

  @doc """
  Convert a Nickel manifest to unified format.
  Uses nickel-lang CLI for evaluation.
  """
  def convert_nickel_manifest(path) do
    case System.cmd("nickel", ["export", "--format", "json", path], stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, json} -> {:ok, json_to_manifest(json)}
          {:error, _} -> {:error, "Failed to parse nickel output as JSON"}
        end

      {error, _code} ->
        {:error, "nickel export failed: #{error}"}
    end
  rescue
    e in ErlangError ->
      {:error, "nickel not found: #{inspect(e)}"}
  end

  @doc """
  Convert an Idris2 pack manifest to unified format.
  """
  def convert_idris2_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        # Idris2 pack uses .ipkg format - simple key-value parsing
        manifest = parse_ipkg(content)
        {:ok, manifest}

      {:error, reason} ->
        {:error, "Failed to read ipkg: #{reason}"}
    end
  end

  @doc """
  Convert any manifest file to unified format.
  Auto-detects format based on filename.
  """
  def convert_manifest(path) do
    cond do
      String.ends_with?(path, ".ncl") ->
        convert_nickel_manifest(path)

      String.ends_with?(path, ".ipkg") ->
        convert_idris2_manifest(path)

      String.ends_with?(path, "package.json") ->
        convert_npm_manifest(path)

      String.ends_with?(path, "Cargo.toml") ->
        convert_cargo_manifest(path)

      String.ends_with?(path, "mix.exs") ->
        convert_mix_manifest(path)

      String.ends_with?(path, "pyproject.toml") ->
        convert_pyproject_manifest(path)

      true ->
        {:error, "Unknown manifest format: #{path}"}
    end
  end

  defp convert_npm_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, json} -> {:ok, json_to_manifest(json)}
          {:error, _} -> {:error, "Invalid package.json"}
        end

      {:error, reason} ->
        {:error, "Failed to read package.json: #{reason}"}
    end
  end

  defp convert_cargo_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        case Toml.decode(content) do
          {:ok, toml} ->
            pkg = toml["package"] || %{}
            {:ok, %ManifestFormat{
              name: pkg["name"] || "",
              version: pkg["version"] || "0.0.0",
              description: pkg["description"],
              license: pkg["license"],
              repository: pkg["repository"],
              authors: pkg["authors"] || [],
              keywords: pkg["keywords"] || [],
              dependencies: toml["dependencies"] || %{},
              dev_dependencies: toml["dev-dependencies"] || %{},
              source_forth: :cargo,
              raw_manifest: toml
            }}

          {:error, reason} ->
            {:error, "Failed to parse Cargo.toml: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read Cargo.toml: #{reason}"}
    end
  end

  defp convert_mix_manifest(path) do
    # Mix.exs requires Elixir evaluation - fall back to regex parsing
    case File.read(path) do
      {:ok, content} ->
        name = extract_mix_field(content, "app")
        version = extract_mix_field(content, "version")
        {:ok, %ManifestFormat{
          name: name || "unknown",
          version: version || "0.0.0",
          source_forth: :hex,
          raw_manifest: %{"raw" => content}
        }}

      {:error, reason} ->
        {:error, "Failed to read mix.exs: #{reason}"}
    end
  end

  defp convert_pyproject_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        case Toml.decode(content) do
          {:ok, toml} ->
            proj = toml["project"] || toml["tool"]["poetry"] || %{}
            {:ok, %ManifestFormat{
              name: proj["name"] || "",
              version: proj["version"] || "0.0.0",
              description: proj["description"],
              license: extract_license(proj["license"]),
              authors: extract_authors(proj["authors"]),
              keywords: proj["keywords"] || [],
              dependencies: extract_pypi_deps(proj["dependencies"]),
              dev_dependencies: extract_pypi_deps(get_in(proj, ["optional-dependencies", "dev"]) || []),
              source_forth: :pypi,
              raw_manifest: toml
            }}

          {:error, reason} ->
            {:error, "Failed to parse pyproject.toml: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read pyproject.toml: #{reason}"}
    end
  end

  # =============================================================================
  # Mode 2: Agentic Fetch
  # =============================================================================

  @doc """
  Agentic package discovery - uses LLM/agent to find packages
  when traditional registry lookup fails.

  This mode is useful for:
  - Finding packages by description rather than exact name
  - Cross-ecosystem package discovery
  - Resolving ambiguous package requests
  """
  def agentic_resolve(query, opts \\ []) do
    # For now, returns a placeholder - actual implementation
    # would integrate with an LLM/agent service
    forths = Keyword.get(opts, :forths, [:npm, :cargo, :hex, :pypi])

    {:ok, %{
      query: query,
      candidates: [],
      forths_searched: forths,
      status: :not_implemented,
      message: "Agentic fetch requires agent service integration"
    }}
  end

  # =============================================================================
  # Mode 3: Connection Ports (System Package Managers)
  # =============================================================================

  @connection_ports %{
    deb: %ConnectionPort{
      target: :deb,
      command: "apt-get",
      convert_script: "fpm -s dir -t deb"
    },
    rpm: %ConnectionPort{
      target: :rpm,
      command: "dnf",
      convert_script: "fpm -s dir -t rpm"
    },
    winget: %ConnectionPort{
      target: :winget,
      command: "winget",
      convert_script: nil
    },
    choco: %ConnectionPort{
      target: :choco,
      command: "choco",
      convert_script: nil
    },
    scoop: %ConnectionPort{
      target: :scoop,
      command: "scoop",
      convert_script: nil
    },
    pacman: %ConnectionPort{
      target: :pacman,
      command: "pacman",
      convert_script: "makepkg"
    },
    homebrew: %ConnectionPort{
      target: :homebrew,
      command: "brew"
    },
    nix: %ConnectionPort{
      target: :nix,
      command: "nix-env"
    },
    guix: %ConnectionPort{
      target: :guix,
      command: "guix"
    },
    flatpak: %ConnectionPort{
      target: :flatpak,
      command: "flatpak"
    },
    rpm_ostree: %ConnectionPort{
      target: :rpm_ostree,
      command: "rpm-ostree"
    },
    dnfinition: %ConnectionPort{
      target: :dnfinition,
      command: "dnfinition"
    },
    snap: %ConnectionPort{
      target: :snap,
      command: "snap"
    }
  }

  @doc """
  Check if a system package manager is available.
  """
  def check_connection_port(target) do
    case Map.get(@connection_ports, target) do
      nil ->
        {:error, "Unknown connection port: #{target}"}

      %ConnectionPort{command: cmd} ->
        case System.find_executable(cmd) do
          nil -> {:error, "#{cmd} not found in PATH"}
          path -> {:ok, %{target: target, command: cmd, path: path}}
        end
    end
  end

  @doc """
  List available connection ports on this system.
  """
  def available_connection_ports do
    @connection_ports
    |> Enum.map(fn {target, _} -> {target, check_connection_port(target)} end)
    |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)
    |> Enum.map(fn {target, {:ok, info}} -> {target, info} end)
    |> Map.new()
  end

  @doc """
  Export a package to a system package format.
  """
  def export_to_port(%ResolvedPackage{} = pkg, target) when is_atom(target) do
    case Map.get(@connection_ports, target) do
      nil ->
        {:error, "Unknown target: #{target}"}

      %ConnectionPort{convert_script: nil} ->
        {:error, "No converter available for #{target}"}

      %ConnectionPort{convert_script: script} ->
        IO.puts("Would run: #{script} for #{pkg.package}@#{pkg.version}")
        {:ok, :export_not_implemented}
    end
  end

  @doc """
  Install package via connection port (delegate to system PM).
  """
  def install_via_port(package, target, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)

    case Map.get(@connection_ports, target) do
      nil ->
        {:error, "Unknown target: #{target}"}

      %ConnectionPort{command: cmd} ->
        install_cmd = build_install_command(cmd, target, package, opts)

        if dry_run do
          {:ok, %{command: install_cmd, dry_run: true}}
        else
          case System.cmd(cmd, install_args(target, package, opts), stderr_to_stdout: true) do
            {output, 0} -> {:ok, output}
            {error, code} -> {:error, "#{cmd} failed (#{code}): #{error}"}
          end
        end
    end
  end

  # =============================================================================
  # Toolchain Detection
  # =============================================================================

  @toolchains %{
    npm: ["node", "npm", "deno", "bun"],
    cargo: ["cargo", "rustc"],
    hex: ["mix", "elixir"],
    pypi: ["python", "python3", "pip", "pip3"],
    gem: ["ruby", "gem"],
    nuget: ["dotnet"],
    maven: ["mvn", "java"],
    pub: ["dart", "flutter"],
    go: ["go"]
  }

  @doc """
  Check if the toolchain for a forth is installed.
  """
  def check_toolchain(forth) when is_atom(forth) do
    case Map.get(@toolchains, forth) do
      nil -> {:ok, :no_toolchain_required}
      commands ->
        found = Enum.filter(commands, &System.find_executable/1)
        if Enum.empty?(found) do
          {:error, %{
            forth: forth,
            required: commands,
            message: "#{forth} toolchain not found. Install one of: #{Enum.join(commands, ", ")}"
          }}
        else
          {:ok, %{forth: forth, available: found}}
        end
    end
  end

  @doc """
  Get toolchain status for all forths.
  """
  def toolchain_status do
    Enum.map(@toolchains, fn {forth, _} ->
      {forth, check_toolchain(forth)}
    end)
    |> Map.new()
  end

  # =============================================================================
  # Cross-Registry Discovery
  # =============================================================================

  @doc """
  Discover a package across all registries without specifying a forth.
  Returns availability info for each registry.
  """
  def discover(package_name, opts \\ []) do
    forths_to_search = Keyword.get(opts, :forths, [:npm, :cargo, :hex, :pypi, :gem, :nuget, :maven, :pub, :go])

    results = Enum.map(forths_to_search, fn forth ->
      toolchain_status = check_toolchain(forth)
      availability = check_registry_availability(forth, package_name)

      %{
        forth: forth,
        available: match?({:ok, _}, availability),
        availability_info: availability,
        toolchain_installed: match?({:ok, _}, toolchain_status),
        toolchain_info: toolchain_status
      }
    end)

    available = Enum.filter(results, & &1.available)
    missing_toolchain = Enum.filter(available, &(not &1.toolchain_installed))

    %{
      package: package_name,
      found_in: Enum.map(available, & &1.forth),
      results: results,
      recommendations: build_recommendations(package_name, available, missing_toolchain),
      alternatives: suggest_alternatives(package_name, forths_to_search)
    }
  end

  defp check_registry_availability(forth, package_name) do
    alias Opsm.Registries.Registry

    case Registry.exists?(forth, package_name) do
      true ->
        case Registry.fetch(forth, package_name) do
          {:ok, pkg} -> {:ok, pkg}
          {:error, reason} -> {:error, reason}
        end
      false ->
        {:error, :not_found}
    end
  end

  defp build_recommendations(package_name, available, missing_toolchain) do
    recs = []

    recs = if Enum.empty?(available) do
      recs ++ ["Package '#{package_name}' not found in any registry. Try 'opsm search #{package_name}'"]
    else
      recs ++ ["Package '#{package_name}' available from: #{Enum.map(available, & &1.forth) |> Enum.join(", ")}"]
    end

    recs = if not Enum.empty?(missing_toolchain) do
      missing = Enum.map(missing_toolchain, fn r ->
        case r.toolchain_info do
          {:error, info} -> "#{r.forth}: #{info.message}"
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

      recs ++ ["Missing toolchains for some registries:"] ++ Enum.map(missing, &("  - " <> &1))
    else
      recs
    end

    recs
  end

  defp suggest_alternatives(package_name, _forths) do
    # In a full implementation, this would use package metadata to suggest alternatives
    # e.g., if searching for "axios" in cargo, suggest "reqwest"
    known_alternatives = %{
      "axios" => %{npm: ["axios"], cargo: ["reqwest", "ureq"], hex: ["req", "httpoison"]},
      "lodash" => %{npm: ["lodash"], cargo: [], hex: [], pypi: ["toolz"]},
      "express" => %{npm: ["express", "fastify", "koa"], cargo: ["actix-web", "axum"], hex: ["phoenix", "plug"]},
      "react" => %{npm: ["react"], cargo: ["dioxus", "yew", "leptos"]},
      "django" => %{pypi: ["django", "flask", "fastapi"]},
      "rails" => %{gem: ["rails", "sinatra", "hanami"]},
      "spring" => %{maven: ["spring-boot"], cargo: ["actix-web"], go: ["gin", "echo"]}
    }

    Map.get(known_alternatives, String.downcase(package_name), %{})
  end

  # =============================================================================
  # Unified Resolution
  # =============================================================================

  @doc """
  Resolve a package across all enabled forths.
  """
  def resolve(%InstallRequest{} = request) do
    forths_to_search =
      if request.forth do
        case get_forth(request.forth) do
          nil -> []
          forth -> [forth]
        end
      else
        enabled_forths()
      end

    results =
      forths_to_search
      |> Enum.map(fn forth -> {forth.name, resolve_from_forth(forth, request)} end)
      |> Enum.filter(fn {_, result} -> match?({:ok, _}, result) end)

    case results do
      [] -> {:error, "Package #{request.package} not found in any registry"}
      [{_forth, {:ok, pkg}} | _] -> {:ok, pkg}
    end
  end

  defp resolve_from_forth(%ForthConfig{federation_mode: :manifest_convert} = forth, _request) do
    # Would make HTTP request to registry API
    {:error, "Registry fetch not yet implemented for #{forth.name}"}
  end

  defp resolve_from_forth(%ForthConfig{federation_mode: :connection_port} = forth, request) do
    install_via_port(request.package, forth.forth_type, dry_run: true)
  end

  defp resolve_from_forth(%ForthConfig{federation_mode: :agentic_fetch}, request) do
    agentic_resolve(request.package)
  end

  # =============================================================================
  # Helpers
  # =============================================================================

  defp json_to_manifest(json) when is_map(json) do
    %ManifestFormat{
      name: json["name"] || "",
      version: json["version"] || "0.0.0",
      description: json["description"],
      license: json["license"],
      homepage: json["homepage"],
      repository: extract_repo(json["repository"]),
      authors: extract_authors(json["author"] || json["authors"]),
      keywords: json["keywords"] || [],
      dependencies: json["dependencies"] || %{},
      dev_dependencies: json["devDependencies"] || %{},
      optional_dependencies: json["optionalDependencies"] || %{},
      peer_dependencies: json["peerDependencies"] || %{},
      bin: json["bin"] || %{},
      scripts: json["scripts"] || %{},
      source_forth: :npm,
      raw_manifest: json
    }
  end

  defp extract_repo(nil), do: nil
  defp extract_repo(url) when is_binary(url), do: url
  defp extract_repo(%{"url" => url}), do: url
  defp extract_repo(_), do: nil

  defp extract_authors(nil), do: []
  defp extract_authors(author) when is_binary(author), do: [author]
  defp extract_authors(authors) when is_list(authors) do
    Enum.map(authors, fn
      a when is_binary(a) -> a
      %{"name" => name} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  defp extract_authors(_), do: []

  defp extract_license(nil), do: nil
  defp extract_license(license) when is_binary(license), do: license
  defp extract_license(%{"text" => text}), do: text
  defp extract_license(_), do: nil

  defp extract_pypi_deps(nil), do: %{}
  defp extract_pypi_deps(deps) when is_list(deps) do
    deps
    |> Enum.map(&parse_pypi_dep/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end
  defp extract_pypi_deps(deps) when is_map(deps), do: deps

  defp parse_pypi_dep(dep) when is_binary(dep) do
    case Regex.run(~r/^([a-zA-Z0-9_-]+)(.*)$/, dep) do
      [_, name, version] -> {name, String.trim(version)}
      _ -> nil
    end
  end
  defp parse_pypi_dep(_), do: nil

  defp parse_ipkg(content) do
    lines = String.split(content, "\n")
    fields = Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, "=", parts: 2) do
        [key, value] ->
          Map.put(acc, String.trim(key), String.trim(value))
        _ ->
          acc
      end
    end)

    %ManifestFormat{
      name: fields["package"] || "unknown",
      version: fields["version"] || "0.0.0",
      description: fields["brief"],
      authors: parse_authors_field(fields["authors"]),
      source_forth: :custom,
      raw_manifest: fields
    }
  end

  defp parse_authors_field(nil), do: []
  defp parse_authors_field(authors) do
    authors
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  defp extract_mix_field(content, field) do
    case Regex.run(~r/#{field}:\s*:?["']?([^"',\n]+)/, content) do
      [_, value] -> String.trim(value)
      _ -> nil
    end
  end

  defp build_install_command(cmd, target, package, opts) do
    args = install_args(target, package, opts)
    "#{cmd} #{Enum.join(args, " ")}"
  end

  defp install_args(:deb, package, _opts), do: ["install", "-y", package]
  defp install_args(:rpm, package, _opts), do: ["install", "-y", package]
  defp install_args(:rpm_ostree, package, _opts), do: ["install", package]
  defp install_args(:dnfinition, package, _opts), do: ["install", package]
  defp install_args(:pacman, package, _opts), do: ["-S", "--noconfirm", package]
  defp install_args(:homebrew, package, _opts), do: ["install", package]
  defp install_args(:nix, package, _opts), do: ["-iA", "nixpkgs.#{package}"]
  defp install_args(:guix, package, _opts), do: ["install", package]
  defp install_args(:flatpak, package, _opts), do: ["install", "-y", package]
  defp install_args(:snap, package, _opts), do: ["install", package]
  defp install_args(:winget, package, _opts), do: ["install", "--accept-package-agreements", package]
  defp install_args(:choco, package, _opts), do: ["install", "-y", package]
  defp install_args(:scoop, package, _opts), do: ["install", package]
  defp install_args(_, package, _opts), do: ["install", package]
end
