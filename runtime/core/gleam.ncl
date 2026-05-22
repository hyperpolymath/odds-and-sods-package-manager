# SPDX-License-Identifier: MPL-2.0
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "gleam",
  description = "gleam — A friendly language for building type-safe systems",
  repository = "https://github.com/gleam-lang/gleam",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "gleam-v{{version}}-x86_64-unknown-linux-musl.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "gleam-v{{version}}-aarch64-unknown-linux-musl.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "gleam-v{{version}}-x86_64-apple-darwin.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "gleam-v{{version}}-aarch64-apple-darwin.tar.gz", archive_format = 'TarGz },
    ],
    strip_components = 0,
  },
  executables = ["gleam"],
  health_check = "gleam --version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["gleam", "beam"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
