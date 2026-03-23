# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "julia",
  description = "julia — High-performance dynamic programming language",
  repository = "https://github.com/JuliaLang/julia",
  homepage = "https://julialang.org",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "julia-{{version}}-linux-x86_64.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "julia-{{version}}-linux-aarch64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "julia-{{version}}-mac64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "julia-{{version}}-macaarch64.tar.gz", archive_format = 'TarGz },
    ],
    strip_components = 1,
  },
  executables = ["julia"],
  health_check = "julia --version",
  facets = { function = ['Runtime, 'Compiler], ecosystem = ["julia"], usage = ['Interactive, 'Batch], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
