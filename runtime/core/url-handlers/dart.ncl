# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Dart / Flutter SDK plugin — custom URL handler for storage.googleapis.com.
# Replaces asdf-dart.  Dart SDK releases are on Google Cloud Storage.
# Note: Flutter/Dart is BANNED as a mobile framework (use Tauri or Dioxus).
# This plugin is for running Dart tools only.

{
  name = "dart",
  description = "Dart SDK — TOOL USE ONLY. Flutter/Dart is banned; use Tauri/Dioxus for mobile.",
  repository = "https://github.com/dart-lang/sdk",
  homepage = "https://dart.dev",

  version_source = 'CustomUrl,
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  url_handler = {
    # Dart version feed from releases channel
    versions_url = "https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION",
    # Fallback: versions are listed at:
    # https://storage.googleapis.com/dart-archive/channels/stable/release/
    # We use the GitHub releases as primary version source for listing
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://storage.googleapis.com/dart-archive/channels/stable/release/{{version}}/sdk/dartsdk-{{dart_os}}-{{dart_arch}}-release.zip",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "dartsdk-linux-x64-release.zip",
        archive_format = 'Zip,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "dartsdk-linux-arm64-release.zip",
        archive_format = 'Zip,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "dartsdk-macos-x64-release.zip",
        archive_format = 'Zip,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "dartsdk-macos-arm64-release.zip",
        archive_format = 'Zip,
      },
      {
        platform = 'WindowsAmd64,
        archive_name_template = "dartsdk-windows-x64-release.zip",
        archive_format = 'Zip,
      },
    ],
    strip_components = 1,
    subdirectory = "dart-sdk",
  },

  executables = ["dart", "dartfmt", "pub"],
  health_check = "dart --version",

  facets = {
    function = ['Runtime, 'Compiler],
    ecosystem = ["dart"],
    usage = ['Batch, 'Oneshot],
    tier = 'Upstream,
  },

  asdf_origin = "https://github.com/asdf-community/asdf-dart",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
