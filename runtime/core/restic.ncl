# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: restic
# Auto-converted from asdf plugin: asdf-restic-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let RuntimePlugin = import "../contract/runtime-plugin.ncl" in

{
  name = "restic",
  description = "restic — managed by OPSM runtime",
  repository = "https://github.com/restic/restic",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "restic-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "restic-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "restic-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "restic-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 1,
  },

  executables = ["restic"],
  health_check = "restic --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-restic-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
