# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: syft
# Auto-converted from asdf plugin: asdf-syft-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let RuntimePlugin = import "../contract/runtime-plugin.ncl" in

{
  name = "syft",
  description = "syft — managed by OPSM runtime",
  repository = "https://github.com/anchore/syft",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "syft-{{version}}-linux-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "syft-{{version}}-linux-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "syft-{{version}}-darwin-amd64.{{ext}}",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "syft-{{version}}-darwin-arm64.{{ext}}",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 1,
  },

  executables = ["syft"],
  health_check = "syft --version",

  facets = {
    function = ['Security],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-syft-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
