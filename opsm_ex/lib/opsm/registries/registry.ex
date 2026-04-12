# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Registries.Registry do
  @moduledoc """
  Unified registry dispatcher.
  Routes package requests to the appropriate registry client.
  Includes caching for improved performance.

  Supports 117+ registry adapters across:
  - Major language ecosystems (npm, cargo, hex, pypi, gem, go, pub, hackage, nuget, maven)
  - Extended language ecosystems (packagist, cpan, cran, conda, cocoapods, opam, clojars, etc.)
  - System package managers (apt, rpm, alpine, homebrew, nix, flatpak, snap, guix, etc.)
  - Container/cloud registries (docker hub, helm, buildpacks, k8s operators, etc.)
  - IDE/editor plugins (vscode, jetbrains, sublime, vim, eclipse, emacs)
  - CDN/asset registries (jsdelivr, cdnjs, webjars)
  - Niche/custom ecosystems (eclexia, oblibeny, agentic, etc.)
  """

  # Major ecosystems
  alias Opsm.Registries.{Npm, Crates, Hex, Pypi, RubyGems, GoModules, PubDev,
    Hackage, NuGet, Maven}

  # Extended language ecosystems
  alias Opsm.Registries.{Packagist, Cpan, Cran, Conda, CocoaPods, Opam, Clojars,
    LuaRocks, Terraform, Jsr, Conan, SwiftPM, Elm, Vcpkg, JuliaGeneral,
    Dub, Shard, Raku, Raco, Chicken, Alire, Stackage, Pear, Pecl,
    SbtPlugins, GradlePlugins, DenoX, CargoBinstall, Bower}

  # System package managers
  alias Opsm.Registries.{Homebrew, HomebrewCask, Nix, NixFlakes, NixDarwin,
    Apt, Rpm, Alpine, Flatpak, Snap, Guix, Macports, Portage, Xbps,
    Zypper, Aur, Pacstall, Solus, Spack, Pkgsrc, Freebsd, FpmRegistry}

  # Container/cloud/infra registries
  alias Opsm.Registries.{DockerHub, Helm, Buildpacks, K8sOperators, Pulumi,
    TektonHub, AnsibleGalaxy, ChefSupermarket, PuppetForge, ScoopApi, WingetApi}

  # IDE/editor/plugin registries
  alias Opsm.Registries.{VscodeMarketplace, Jetbrains, Sublime, VimPlugins,
    EclipseMarketplace, Melpa, Elpa, Grafana, OpenUpm, Godot}

  # CDN/asset/meta registries
  alias Opsm.Registries.{JsDelivr, Cdnjs, WebJars, GithubPackages, GitlabPackages,
    WordPress, WordPressThemes, Wapm, Bioconductor, Astrolabe, Vpm}

  # Niche/custom ecosystems
  alias Opsm.Registries.{Nimble, Idris2, Git, Agentic, Oblibeny, MyLang,
    JuliaTheViper, ErrorLang, Eclexia, AffineScript, RattleScript}

  # Hyperpolymath Forge Registry + new nextgen language/database adapters
  alias Opsm.Registries.{HyperpPolymathForge, Betlang, Ephapax, Phronesis,
    Tangle, Wokelang, Lithoglyph, Nqc, QuandleDB}

  alias Opsm.Cache

  @registry_modules %{
    # =========================================================================
    # Major Language Ecosystems (10 modules, 20 aliases)
    # =========================================================================
    npm: Npm,
    node: Npm,
    cargo: Crates,
    crates: Crates,
    rust: Crates,
    hex: Hex,
    elixir: Hex,
    erlang: Hex,
    pypi: Pypi,
    python: Pypi,
    pip: Pypi,
    gem: RubyGems,
    rubygems: RubyGems,
    ruby: RubyGems,
    go: GoModules,
    golang: GoModules,
    pub: PubDev,
    dart: PubDev,
    flutter: PubDev,
    hackage: Hackage,
    haskell: Hackage,
    nuget: NuGet,
    dotnet: NuGet,
    csharp: NuGet,
    fsharp: NuGet,
    maven: Maven,
    java: Maven,
    kotlin: Maven,

    # =========================================================================
    # Extended Language Ecosystems (29 modules)
    # =========================================================================
    packagist: Packagist,
    php: Packagist,
    composer: Packagist,
    cpan: Cpan,
    perl: Cpan,
    metacpan: Cpan,
    cran: Cran,
    r: Cran,
    conda: Conda,
    anaconda: Conda,
    cocoapods: CocoaPods,
    pods: CocoaPods,
    ios: CocoaPods,
    opam: Opam,
    ocaml: Opam,
    clojars: Clojars,
    clojure: Clojars,
    luarocks: LuaRocks,
    lua: LuaRocks,
    terraform: Terraform,
    tf: Terraform,
    jsr: Jsr,
    deno: Jsr,
    conan: Conan,
    cpp: Conan,
    swift: SwiftPM,
    spm: SwiftPM,
    elm: Elm,
    vcpkg: Vcpkg,
    julia: JuliaGeneral,
    juliageneral: JuliaGeneral,
    dub: Dub,
    dlang: Dub,
    shard: Shard,
    crystal: Shard,
    raku: Raku,
    perl6: Raku,
    raco: Raco,
    racket: Raco,
    chicken: Chicken,
    scheme: Chicken,
    alire: Alire,
    ada: Alire,
    stackage: Stackage,
    haskell_stackage: Stackage,
    pear: Pear,
    php_pear: Pear,
    pecl: Pecl,
    php_pecl: Pecl,
    sbt_plugins: SbtPlugins,
    sbt: SbtPlugins,
    scala: SbtPlugins,
    gradle_plugins: GradlePlugins,
    gradle: GradlePlugins,
    deno_x: DenoX,
    deno_land: DenoX,
    cargo_binstall: CargoBinstall,
    binstall: CargoBinstall,
    bower: Bower,

    # =========================================================================
    # System Package Managers (22 modules)
    # =========================================================================
    homebrew: Homebrew,
    brew: Homebrew,
    homebrew_cask: HomebrewCask,
    cask: HomebrewCask,
    nix: Nix,
    nixpkgs: Nix,
    nix_flakes: NixFlakes,
    flakes: NixFlakes,
    nix_darwin: NixDarwin,
    darwin: NixDarwin,
    apt: Apt,
    deb: Apt,
    debian: Apt,
    ubuntu: Apt,
    rpm: Rpm,
    dnf: Rpm,
    fedora: Rpm,
    yum: Rpm,
    alpine: Alpine,
    apk: Alpine,
    flatpak: Flatpak,
    flathub: Flatpak,
    snap: Snap,
    snapcraft: Snap,
    guix: Guix,
    macports: Macports,
    ports: Macports,
    portage: Portage,
    gentoo: Portage,
    emerge: Portage,
    xbps: Xbps,
    void: Xbps,
    zypper: Zypper,
    opensuse: Zypper,
    suse: Zypper,
    aur: Aur,
    arch: Aur,
    pacstall: Pacstall,
    solus: Solus,
    eopkg: Solus,
    spack: Spack,
    hpc: Spack,
    pkgsrc: Pkgsrc,
    netbsd: Pkgsrc,
    freebsd: Freebsd,
    pkg_freebsd: Freebsd,
    fpm: FpmRegistry,

    # =========================================================================
    # Container / Cloud / Infra Registries (11 modules)
    # =========================================================================
    docker: DockerHub,
    docker_hub: DockerHub,
    oci: DockerHub,
    helm: Helm,
    helm_charts: Helm,
    buildpacks: Buildpacks,
    cnb: Buildpacks,
    k8s_operators: K8sOperators,
    olm: K8sOperators,
    pulumi: Pulumi,
    tekton: TektonHub,
    tekton_hub: TektonHub,
    ansible: AnsibleGalaxy,
    ansible_galaxy: AnsibleGalaxy,
    chef: ChefSupermarket,
    chef_supermarket: ChefSupermarket,
    puppet: PuppetForge,
    puppet_forge: PuppetForge,
    scoop: ScoopApi,
    scoop_api: ScoopApi,
    winget: WingetApi,
    winget_api: WingetApi,

    # =========================================================================
    # IDE / Editor / Plugin Registries (10 modules)
    # =========================================================================
    vscode: VscodeMarketplace,
    vscode_marketplace: VscodeMarketplace,
    jetbrains: Jetbrains,
    intellij: Jetbrains,
    sublime: Sublime,
    sublime_text: Sublime,
    vim: VimPlugins,
    vim_plugins: VimPlugins,
    neovim: VimPlugins,
    eclipse: EclipseMarketplace,
    eclipse_marketplace: EclipseMarketplace,
    melpa: Melpa,
    emacs: Melpa,
    elpa: Elpa,
    gnu_elpa: Elpa,
    grafana: Grafana,
    grafana_plugins: Grafana,
    openupm: OpenUpm,
    unity: OpenUpm,
    godot: Godot,
    godot_asset: Godot,

    # =========================================================================
    # CDN / Asset / Meta Registries (11 modules)
    # =========================================================================
    jsdelivr: JsDelivr,
    cdn: JsDelivr,
    cdnjs: Cdnjs,
    webjars: WebJars,
    github_packages: GithubPackages,
    ghcr: GithubPackages,
    gitlab_packages: GitlabPackages,
    gitlab_registry: GitlabPackages,
    wordpress: WordPress,
    wp_plugins: WordPress,
    wordpress_themes: WordPressThemes,
    wp_themes: WordPressThemes,
    wapm: Wapm,
    wasm: Wapm,
    bioconductor: Bioconductor,
    bioc: Bioconductor,
    astrolabe: Astrolabe,
    vpm: Vpm,
    vrchat: Vpm,

    # =========================================================================
    # Niche / Custom Ecosystems (9 modules)
    # =========================================================================
    nimble: Nimble,
    nim: Nimble,
    idris2: Idris2,
    idris: Idris2,
    git: Git,
    agentic: Agentic,
    oblibeny: Oblibeny,
    obli: Oblibeny,
    my_lang: MyLang,
    mylang: MyLang,
    julia_the_viper: JuliaTheViper,
    viper: JuliaTheViper,
    error_lang: ErrorLang,
    error: ErrorLang,
    eclexia: Eclexia,
    ecl: Eclexia,
    affinescript: AffineScript,
    affine: AffineScript,
    afs: AffineScript,
    rattlescript: RattleScript,
    rattle: RattleScript,
    rts: RattleScript,

    # =========================================================================
    # Hyperpolymath Forge Registry (HFR)
    # Auto-indexes every hyperpolymath/* repo that ships opsm.toml.
    # This is the primary registry for ALL hyperpolymath-authored packages.
    # =========================================================================
    hf: HyperpPolymathForge,
    hyperpolymath: HyperpPolymathForge,
    hyperpolymath_forge: HyperpPolymathForge,
    forge: HyperpPolymathForge,

    # =========================================================================
    # nextgen-languages registries (per-language adapters)
    # =========================================================================
    betlang: Betlang,
    bet: Betlang,
    ephapax: Ephapax,
    epx: Ephapax,
    phronesis: Phronesis,
    phro: Phronesis,
    tangle: Tangle,
    krl: Tangle,
    wokelang: Wokelang,
    wok: Wokelang,

    # =========================================================================
    # nextgen-databases registries
    # =========================================================================
    lithoglyph: Lithoglyph,
    litho: Lithoglyph,
    glyphbase: Lithoglyph,
    quandledb: QuandleDB,
    quandle: QuandleDB,
    nqc: Nqc,
    query_calculus: Nqc
  }

  # All primary forth names (for search_all / exists_all? defaults)
  @all_primary_forths [
    # Major
    :npm, :cargo, :hex, :pypi, :gem, :go, :pub, :hackage, :nuget, :maven,
    # Extended
    :packagist, :cpan, :cran, :conda, :cocoapods, :opam, :clojars,
    :luarocks, :terraform, :jsr, :conan, :swift, :elm, :vcpkg, :julia,
    :dub, :shard, :raku, :raco, :chicken, :alire, :stackage, :pear, :pecl,
    :sbt_plugins, :gradle_plugins, :deno_x, :cargo_binstall, :bower,
    # System
    :homebrew, :homebrew_cask, :nix, :nix_flakes, :nix_darwin,
    :apt, :rpm, :alpine, :flatpak, :snap, :guix, :macports, :portage,
    :xbps, :zypper, :aur, :pacstall, :solus, :spack, :pkgsrc, :freebsd, :fpm,
    # Container/cloud
    :docker, :helm, :buildpacks, :k8s_operators, :pulumi, :tekton,
    :ansible, :chef, :puppet, :scoop, :winget,
    # IDE/editor
    :vscode, :jetbrains, :sublime, :vim, :eclipse, :melpa, :elpa,
    :grafana, :openupm, :godot,
    # CDN/meta
    :jsdelivr, :cdnjs, :webjars, :github_packages, :gitlab_packages,
    :wordpress, :wordpress_themes, :wapm, :bioconductor, :astrolabe, :vpm,
    # Niche / custom ecosystems
    :nimble, :idris2, :eclexia, :affinescript, :rattlescript,
    # Hyperpolymath Forge Registry (primary for all HP packages)
    :hf,
    # nextgen-languages
    :betlang, :ephapax, :phronesis, :tangle, :wokelang,
    # nextgen-databases
    :lithoglyph, :quandledb, :nqc
  ]

  @doc """
  Fetch package from specified registry.
  Results are cached for improved performance.
  """
  def fetch(forth, package, version \\ "latest") do
    case get_module(forth) do
      nil ->
        {:error, "Unknown registry: #{forth}"}

      module ->
        cache_key = Cache.package_key(forth, package, version)
        Cache.fetch(cache_key, fn -> module.fetch_package(package, version) end)
    end
  end

  @doc """
  Fetch package bypassing cache.
  """
  def fetch!(forth, package, version \\ "latest") do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.fetch_package(package, version)
    end
  end

  @doc """
  Search across specified registry.
  """
  def search(forth, query, opts \\ []) do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.search(query, opts)
    end
  end

  @doc """
  Check if package exists in registry.
  """
  def exists?(forth, package) do
    case get_module(forth) do
      nil -> false
      module -> module.exists?(package)
    end
  end

  @doc """
  Get all versions from registry.
  """
  def versions(forth, package) do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.versions(package)
    end
  end

  @doc """
  Search across ALL registries in parallel.
  Returns results from each registry.
  Handles task failures gracefully.
  """
  def search_all(query, opts \\ []) do
    forths = Keyword.get(opts, :forths, @all_primary_forths)
    timeout = Keyword.get(opts, :timeout, 15_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        try do
          result = search(forth, query, opts)
          {forth, result}
        rescue
          e -> {forth, {:error, Exception.message(e)}}
        catch
          kind, reason -> {forth, {:error, "#{kind}: #{inspect(reason)}"}}
        end
      end)
    end)

    results = safe_await_many(tasks, timeout)

    results
    |> Enum.flat_map(fn
      {forth, {:ok, packages}} when is_atom(forth) or is_binary(forth) -> [{forth, packages}]
      {forth, {:error, _}} when is_atom(forth) or is_binary(forth) -> [{forth, []}]
      {:error, _} -> []
      _ -> []
    end)
    |> Map.new()
  end

  @doc """
  Check package existence across ALL registries in parallel.
  Returns map of registry -> exists?
  Handles task failures gracefully.
  """
  def exists_all?(package, opts \\ []) do
    forths = Keyword.get(opts, :forths, @all_primary_forths)
    timeout = Keyword.get(opts, :timeout, 10_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        {forth, exists?(forth, package)}
      end)
    end)

    results = safe_await_many(tasks, timeout)

    Enum.map(results, fn
      {forth, exists} when is_boolean(exists) -> {forth, exists}
      {:error, _} -> {:unknown, false}
    end)
    |> Map.new()
  end

  @doc """
  Fetch package from ALL registries where it exists.
  Returns map of registry -> package info.
  Handles task failures gracefully.
  """
  def fetch_all(package, version \\ "latest", opts \\ []) do
    forths = Keyword.get(opts, :forths, @all_primary_forths)
    timeout = Keyword.get(opts, :timeout, 15_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        try do
          result = fetch(forth, package, version)
          {forth, result}
        rescue
          e -> {forth, {:error, Exception.message(e)}}
        catch
          kind, reason -> {forth, {:error, "#{kind}: #{inspect(reason)}"}}
        end
      end)
    end)

    results = safe_await_many(tasks, timeout)

    results
    |> Enum.flat_map(fn
      {forth, {:ok, pkg}} when is_atom(forth) or is_binary(forth) -> [{forth, pkg}]
      _ -> []
    end)
    |> Map.new()
  end

  @doc """
  Get the registry module for a forth.
  """
  def get_module(forth) when is_atom(forth), do: Map.get(@registry_modules, forth)
  def get_module(forth) when is_binary(forth) do
    case safe_to_atom(forth) do
      nil -> nil
      atom -> get_module(atom)
    end
  end

  @doc """
  List all supported registries (primary forth names only).
  """
  def supported_registries do
    @all_primary_forths
    |> Enum.sort()
  end

  @doc """
  List all forth aliases (including aliases).
  """
  def all_forth_aliases do
    @registry_modules
    |> Map.keys()
    |> Enum.sort()
  end

  @doc """
  Count of unique registry adapter modules.
  """
  def adapter_count do
    @registry_modules
    |> Map.values()
    |> Enum.uniq()
    |> length()
  end

  @doc """
  Check if a registry is available/supported.

  ## Examples

      iex> Registry.available?(:npm)
      true

      iex> Registry.available?(:unknown)
      false
  """
  def available?(forth) when is_atom(forth) do
    Map.has_key?(@registry_modules, forth)
  end

  def available?(forth) when is_binary(forth) do
    case safe_to_atom(forth) do
      nil -> false
      atom -> available?(atom)
    end
  end

  # Helpers

  defp safe_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  @doc false
  # Safely await multiple tasks, catching failures and timeouts
  defp safe_await_many(tasks, timeout) do
    # Use Task.yield_many to avoid crashes on task failure
    results = Task.yield_many(tasks, timeout)

    Enum.map(results, fn
      {_task, {:ok, result}} ->
        result

      {task, {:exit, _reason}} ->
        # Task crashed - extract forth from task if possible
        Task.shutdown(task, :brutal_kill)
        {:error, :task_crashed}

      {task, nil} ->
        # Task timed out
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end)
  end
end
