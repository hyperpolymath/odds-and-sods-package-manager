# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: asdf-ui
# Auto-converted from asdf plugin: asdf-ui-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "asdf-ui",
  description = "asdf-ui — managed by OPSM runtime",
  repository = "https://github.com/hyperpolymath/asdf-tool-plugins",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "asdf-ui-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "asdf-ui-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "asdf-ui-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "asdf-ui-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 1,
  },

  executables = ["asdf-ui"],
  health_check = "asdf-ui --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-ui-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
