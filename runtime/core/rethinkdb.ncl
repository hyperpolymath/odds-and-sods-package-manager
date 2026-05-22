# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: rethinkdb
# Auto-converted from asdf plugin: asdf-rethinkdb-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "rethinkdb",
  description = "rethinkdb — managed by OPSM runtime",
  repository = "https://github.com/rethinkdb/rethinkdb",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "rethinkdb-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "rethinkdb-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "rethinkdb-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "rethinkdb-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 1,
  },

  executables = ["rethinkdb"],
  health_check = "rethinkdb --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-rethinkdb-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
