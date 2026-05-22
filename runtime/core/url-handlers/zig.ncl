# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Zig runtime plugin — custom URL handler for ziglang.org JSON index.
# Replaces the asdf-zig plugin.  Uses 'JsonIndex + url_handler to resolve
# versions from https://ziglang.org/download/index.json and build archive URLs.

{
  name = "zig",
  description = "Zig systems programming language — memory safety without GC, comptime, cross-compilation",
  repository = "https://github.com/ziglang/zig",
  homepage = "https://ziglang.org",

  version_source = 'JsonIndex,
  # Skip master/devbuilds; only semver releases
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  # Custom URL handler overrides the default GitHub Releases logic.
  # The provisioner reads this field and delegates to UrlHandler.Zig.
  url_handler = {
    versions_url = "https://ziglang.org/download/index.json",
    # The JSON index keys ARE the version strings (plus "master").
    # version_key_pattern filters out non-release keys.
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    # Archive URL template — variables: {{version}}, {{os}}, {{arch}}, {{ext}}
    # Zig uses its own platform naming: x86_64-linux, aarch64-linux, etc.
    archive_url_template = "https://ziglang.org/download/{{version}}/zig-{{zig_platform}}-{{version}}.tar.xz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "zig-linux-x86_64-{{version}}.tar.xz",
        archive_format = 'TarXz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "zig-linux-aarch64-{{version}}.tar.xz",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "zig-macos-x86_64-{{version}}.tar.xz",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "zig-macos-aarch64-{{version}}.tar.xz",
        archive_format = 'TarXz,
      },
      {
        platform = 'WindowsAmd64,
        archive_name_template = "zig-windows-x86_64-{{version}}.zip",
        archive_format = 'Zip,
      },
    ],
    strip_components = 1,
  },

  executables = ["zig"],
  health_check = "zig version",

  facets = {
    function = ['Compiler, 'Runtime, 'BuildTool],
    ecosystem = ["zig", "systems", "wasm"],
    usage = ['Batch, 'Oneshot],
    tier = 'Core,
  },

  system_dependencies = [],

  asdf_origin = "https://github.com/asdf-community/asdf-zig",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
