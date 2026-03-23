# SPDX-License-Identifier: PMPL-1.0-or-later
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

  version_source = 'JsonIndex,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "zig-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "zig-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "zig-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "zig-{{version}}-darwin-arm64.{{ext}}",
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
