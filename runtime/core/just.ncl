# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# OPSM Runtime Plugin: just
# A command runner — handy way to save and run project-specific commands.

let RuntimePlugin = import "../contract/runtime-plugin.ncl" in

{
  name = "just",
  description = "just — A command runner for project-specific recipes",
  repository = "https://github.com/casey/just",
  homepage = "https://just.systems",

  version_source = 'GitHubReleases,

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "just-{{version}}-x86_64-unknown-linux-musl.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "just-{{version}}-aarch64-unknown-linux-musl.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "just-{{version}}-x86_64-apple-darwin.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "just-{{version}}-aarch64-apple-darwin.tar.gz",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 0,
  },

  executables = ["just"],
  health_check = "just --version",

  facets = {
    function = ['BuildTool, 'CLI],
    ecosystem = ["polyglot"],
    usage = ['Oneshot],
    tier = 'Core,
  },

  schema_version = "1.0.0",
} | RuntimePlugin
