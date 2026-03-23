# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "typst",
  description = "typst — A new markup-based typesetting system",
  repository = "https://github.com/typst/typst",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "typst-x86_64-unknown-linux-musl.tar.xz", archive_format = 'TarXz },
      { platform = 'LinuxArm64, archive_name_template = "typst-aarch64-unknown-linux-musl.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinAmd64, archive_name_template = "typst-x86_64-apple-darwin.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinArm64, archive_name_template = "typst-aarch64-apple-darwin.tar.xz", archive_format = 'TarXz },
    ],
    strip_components = 1,
  },
  executables = ["typst"],
  health_check = "typst --version",
  facets = { function = ['Compiler, 'CLI], ecosystem = ["typst"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
