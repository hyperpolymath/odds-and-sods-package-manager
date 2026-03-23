# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin Contract
# ============================
# Every runtime plugin definition must satisfy this contract.
# The contract is the spec — if it type-checks, the plugin is valid.
#
# Nickel contracts enforce structure at evaluation time, catching
# malformed plugin definitions before they enter the registry.

# --- Enums ---

let VersionSource = [|
  'GitHubReleases,
  'GitHubTags,
  'GitLabReleases,
  'JsonIndex,
  'CustomApi,
  'LanguageManager,
|] in

let InstallStrategy = [|
  'PrebuiltBinary,
  'BuildFromSource,
  'Both,
  'DelegateToManager,
|] in

let ArchiveFormat = [|
  'TarGz,
  'TarXz,
  'TarBz2,
  'Zip,
  'RawBinary,
  'Dmg,
  'Msi,
  'Deb,
  'Rpm,
|] in

let UsageMode = [|
  'Interactive,
  'Batch,
  'Daemon,
  'Oneshot,
|] in

let ToolFunction = [|
  'Runtime,
  'Compiler,
  'Linter,
  'Formatter,
  'BuildTool,
  'PackageManager,
  'Database,
  'Security,
  'Server,
  'CLI,
  'Editor,
  'Debugger,
  'Profiler,
  'TestRunner,
  'ContainerTool,
  'NetworkTool,
|] in

let Tier = [|
  'Core,
  'Community,
  'Experimental,
  'Upstream,
|] in

let Platform = [|
  'LinuxAmd64,
  'LinuxArm64,
  'DarwinAmd64,
  'DarwinArm64,
  'WindowsAmd64,
  'WindowsArm64,
  'FreebsdAmd64,
|] in

# --- Sub-contracts ---

let PlatformMapping = {
  platform | Platform,
  archive_name_template | String,
  archive_format | ArchiveFormat | default = 'TarGz,
} in

let SystemDependency = {
  name | String,
  check_command | String,
  # Distro-specific package names
  apt | String | optional,
  dnf | String | optional,
  pacman | String | optional,
  brew | String | optional,
  apk | String | optional,
} in

let LegacyFileSupport = {
  filenames | Array String,
  parse_command | String | optional,
} in

let EnvironmentBinding = {
  variable | String,
  value_template | String,
} in

let Contributor = {
  name | String,
  email | String | optional,
  url | String | optional,
} in

# --- Main Contract ---

let RuntimePlugin = {
  # === Identity (required) ===
  name
    | String
    | doc "Tool name as users will type it (e.g., 'zig', 'erlang', 'deno')",

  description
    | String
    | doc "One-line description of what this tool is",

  repository
    | String
    | doc "Upstream source repository URL",

  homepage
    | String
    | optional
    | doc "Project homepage if different from repository",

  # === Versioning (required) ===
  version_source
    | VersionSource
    | doc "How to discover available versions",

  version_pattern
    | String
    | optional
    | doc "Regex to filter/extract version strings from tags (e.g., 'v(.+)')",

  version_sort
    | [| 'Semver, 'Lexicographic, 'Numeric |]
    | default = 'Semver
    | doc "How to sort versions for 'latest' resolution",

  # === Installation (required) ===
  install
    | {
        strategy | InstallStrategy,

        # For PrebuiltBinary / Both
        platforms | Array PlatformMapping | optional,

        # For BuildFromSource / Both
        build_steps | Array String | optional,
        configure_flags | Array String | optional,

        # For DelegateToManager
        delegate_to | String | optional,
        delegate_install_command | String | optional,

        # Common
        strip_components | Number | default = 1,
        subdirectory | String | optional,
      },

  # === Archive name template variables ===
  # Available in archive_name_template:
  #   {{version}}  - resolved version string
  #   {{os}}       - linux, darwin, windows
  #   {{arch}}     - amd64, arm64, 386
  #   {{ext}}      - tar.gz, zip, etc. (from archive_format)

  # === Executables (required) ===
  executables
    | Array String
    | doc "Binary names that become shims (e.g., ['erl', 'erlc', 'rebar3'])",

  # === Health check (required) ===
  health_check
    | String
    | doc "Command to verify the tool works after install (e.g., 'zig version')",

  # === Faceted classification (required) ===
  facets
    | {
        function  | Array ToolFunction,
        ecosystem | Array String,
        usage     | Array UsageMode,
        tier      | Tier,
      },

  # === Optional fields ===

  system_dependencies
    | Array SystemDependency
    | optional
    | doc "System packages needed to build or run this tool",

  environment
    | Array EnvironmentBinding
    | optional
    | doc "Environment variables to set when this tool is active",

  legacy_files
    | LegacyFileSupport
    | optional
    | doc "Support for .nvmrc, .python-version, etc.",

  # === Attribution ===
  contributor
    | Contributor
    | optional
    | doc "Who contributed this plugin definition",

  asdf_origin
    | String
    | optional
    | doc "Original asdf plugin repository for attribution",

  # === Metadata ===
  license
    | String
    | default = "PMPL-1.0-or-later"
    | doc "License for this plugin definition (not the tool itself)",

  schema_version
    | String
    | default = "1.0.0"
    | doc "Contract version this definition was written against",
} in

RuntimePlugin
