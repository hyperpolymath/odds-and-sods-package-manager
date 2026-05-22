# SPDX-License-Identifier: MPL-2.0
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "wasmtime",
  description = "wasmtime — Fast and secure WebAssembly runtime",
  repository = "https://github.com/bytecodealliance/wasmtime",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "wasmtime-v{{version}}-x86_64-linux.tar.xz", archive_format = 'TarXz },
      { platform = 'LinuxArm64, archive_name_template = "wasmtime-v{{version}}-aarch64-linux.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinAmd64, archive_name_template = "wasmtime-v{{version}}-x86_64-macos.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinArm64, archive_name_template = "wasmtime-v{{version}}-aarch64-macos.tar.xz", archive_format = 'TarXz },
    ],
    strip_components = 1,
  },
  executables = ["wasmtime"],
  health_check = "wasmtime --version",
  facets = { function = ['Runtime], ecosystem = ["wasm"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
