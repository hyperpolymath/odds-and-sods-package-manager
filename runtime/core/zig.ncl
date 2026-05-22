# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: zig
# Auto-converted from asdf plugin: asdf-zig-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "zig",
  description = "zig — managed by OPSM runtime",
  repository = "https://github.com/ziglang/zig",

  version_source = 'CustomUrl,
  # Skip master/devbuilds; only semver releases
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",

  # Zig publishes a JSON index (not GitHub Releases).
  # UrlHandler.Zig maps platform → {{zig_platform}} (e.g. linux-x86_64, macos-aarch64).
  url_handler = {
    versions_url = "https://ziglang.org/download/index.json",
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
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
    ],
    strip_components = 1,
  },

  executables = ["zig"],
  health_check = "zig --version",

  facets = {
    function = ['Compiler, 'Runtime],
    ecosystem = ["zig"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-zig-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
