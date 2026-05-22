# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: dhall
# Auto-converted from asdf plugin: asdf-dhall-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "dhall",
  description = "dhall — managed by OPSM runtime",
  repository = "https://github.com/dhall-lang/dhall-haskell",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "dhall-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarBz2,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "dhall-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarBz2,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "dhall-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarBz2,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "dhall-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarBz2,
      },
    ],
    strip_components = 1,
  },

  executables = ["dhall"],
  health_check = "dhall --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-dhall-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
