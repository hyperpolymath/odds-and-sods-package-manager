# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "golang",
  description = "golang — The Go programming language",
  repository = "https://github.com/golang/go",
  homepage = "https://go.dev",
  version_source = 'CustomApi,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "go{{version}}.linux-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "go{{version}}.linux-arm64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "go{{version}}.darwin-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "go{{version}}.darwin-arm64.tar.gz", archive_format = 'TarGz },
    ],
    strip_components = 1,
  },
  executables = ["go", "gofmt"],
  health_check = "go version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["go"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
