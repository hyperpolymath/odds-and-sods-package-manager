# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "dart",
  description = "dart — Client-optimised language for fast apps",
  repository = "https://github.com/dart-lang/sdk",
  homepage = "https://dart.dev",
  version_source = 'CustomUrl,

  # UrlHandler.Dart maps platform → {{dart_os}} (linux/macos/windows), {{dart_arch}} (x64/arm64/ia32)
  # Note: Dart is BANNED as a development language (use Tauri/Dioxus instead).
  # This plugin exists ONLY for Flutter toolchain migration scenarios.
  url_handler = {
    versions_url = "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION",
    archive_url_template = "https://storage.googleapis.com/dart-archive/channels/stable/release/{{version}}/sdk/dartsdk-{{dart_os}}-{{dart_arch}}-release.zip",
  },

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
