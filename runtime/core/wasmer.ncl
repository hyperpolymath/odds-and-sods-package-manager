# SPDX-License-Identifier: MPL-2.0
let RuntimePlugin = import "../contract/runtime-plugin.ncl" in
{
  name = "wasmer",
  description = "wasmer — Universal WebAssembly Runtime",
  repository = "https://github.com/wasmerio/wasmer",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "wasmer-linux-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "wasmer-linux-aarch64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "wasmer-darwin-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "wasmer-darwin-arm64.tar.gz", archive_format = 'TarGz },
    ],
    strip_components = 0,
  },
  executables = ["wasmer"],
  health_check = "wasmer --version",
  facets = { function = ['Runtime], ecosystem = ["wasm"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
