# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: bebop
# Auto-converted from asdf plugin: asdf-bebop-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let RuntimePlugin = import "../contract/runtime-plugin.ncl" in

{
  name = "bebop",
  description = "bebop — managed by OPSM runtime",
  repository = "https://github.com/_ID=",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "bebop-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'Zip,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "bebop-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'Zip,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "bebop-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'Zip,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "bebop-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'Zip,
      },
    ],
    strip_components = 1,
  },

  executables = ["bebopc"],
  health_check = "bebopc --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-bebop-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
