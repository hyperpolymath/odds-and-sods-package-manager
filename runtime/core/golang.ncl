# SPDX-License-Identifier: MPL-2.0
let RuntimePlugin = import "../contract/runtime-plugin.ncl" in
{
  name = "golang",
  description = "golang — The Go programming language",
  repository = "https://github.com/golang/go",
  homepage = "https://go.dev",
  version_source = 'CustomUrl,
  # go.dev/dl returns versions with "go" prefix (e.g. "go1.21.0"); strip for semver sort
  version_pattern = "^go([0-9]+\\.[0-9]+(\\.[0-9]+)?)$",

  # UrlHandler.Golang maps platform → {{go_version}} (e.g. go1.21.0), {{go_os}}, {{go_arch}}
  url_handler = {
    versions_url = "https://go.dev/dl/?mode=json&include=all",
    version_key_pattern = "^go[0-9]+\\.[0-9]+",
    archive_url_template = "https://go.dev/dl/{{go_version}}.{{go_os}}-{{go_arch}}.tar.gz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "go{{version}}.linux-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "go{{version}}.linux-arm64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "go{{version}}.darwin-amd64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "go{{version}}.darwin-arm64.tar.gz", archive_format = 'TarGz },
      { platform = 'WindowsAmd64, archive_name_template = "go{{version}}.windows-amd64.zip", archive_format = 'Zip },
    ],
    # Go unpacks to a "go/" subdirectory — strip it
    strip_components = 1,
    subdirectory = "go",
  },
  executables = ["go", "gofmt"],
  health_check = "go version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["go"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
