# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: cue
# Auto-converted from asdf plugin: asdf-cue-plugin
# Original asdf plugin maintained by hyperpolymath (MIT)
#
# This definition expresses factual data (repository URL, binary name,
# archive format) in OPSM's Nickel contract format. The asdf plugin
# ecosystem's pioneering work is gratefully acknowledged.

let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in

{
  name = "cue",
  description = "cue — managed by OPSM runtime",
  repository = "https://github.com/cue-lang/cue",

  version_source = 'GitHubReleases,

  # CUE release assets use underscores and a 'v' prefix in the version portion:
  # cue_v0.11.0_linux_amd64.tar.gz  (NOT cue-0.11.0-linux-amd64.tar.gz)
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "cue_v{{version}}_linux_amd64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "cue_v{{version}}_linux_arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "cue_v{{version}}_darwin_amd64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "cue_v{{version}}_darwin_arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'WindowsAmd64,
        archive_name_template = "cue_v{{version}}_windows_amd64.zip",
        archive_format = 'Zip,
      },
    ],
    strip_components = 0,
  },

  executables = ["cue"],
  health_check = "cue --version",

  facets = {
    function = ['CLI],
    ecosystem = ["system"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/hyperpolymath/asdf-tool-plugins/tree/main/asdf-cue-plugin",
  schema_version = "1.0.0",
} | RuntimePlugin
