# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "dart",
  description = "dart — Client-optimised language for fast apps",
  repository = "https://github.com/dart-lang/sdk",
  homepage = "https://dart.dev",
  version_source = 'CustomApi,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "dartsdk-linux-x64-release.zip", archive_format = 'Zip },
      { platform = 'LinuxArm64, archive_name_template = "dartsdk-linux-arm64-release.zip", archive_format = 'Zip },
      { platform = 'DarwinAmd64, archive_name_template = "dartsdk-macos-x64-release.zip", archive_format = 'Zip },
      { platform = 'DarwinArm64, archive_name_template = "dartsdk-macos-arm64-release.zip", archive_format = 'Zip },
    ],
    strip_components = 1,
  },
  executables = ["dart"],
  health_check = "dart --version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["dart", "flutter"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
