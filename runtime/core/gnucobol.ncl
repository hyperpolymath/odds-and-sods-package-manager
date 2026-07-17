# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: gnucobol
# Auto-converted from asdf plugin: asdf-cobol-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let RuntimePlugin = import "../contract/runtime-plugin.ncl" in

{
  name = "gnucobol",
  description = "gnucobol — managed by OPSM runtime",
  repository = "https://sourceforge.net/projects/gnucobol",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "gnucobol-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "gnucobol-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "gnucobol-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarXz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "gnucobol-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarXz,
      },
    ],
    strip_components = 1,
  },

  executables = ["gnucobol"],
  health_check = "gnucobol --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-cobol-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
