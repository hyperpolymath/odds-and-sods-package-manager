# SPDX-License-Identifier: MPL-2.0
let RuntimePlugin = import "../contract/runtime-plugin.ncl" in
{
  name = "nim",
  description = "nim — Efficient, expressive, elegant systems language",
  repository = "https://github.com/nim-lang/Nim",
  homepage = "https://nim-lang.org",
  # Nim releases are on GitHub but the download URL is nim-lang.org, not GitHub assets.
  version_source = 'GitHubReleases,
  # GitHub releases have no v-prefix (e.g. "2.0.2" not "v2.0.2")
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",

  # GitHub Releases list versions; actual binaries served from nim-lang.org.
  # UrlHandler.Nim maps platform → {{nim_os}} (linux/macos) and {{nim_arch}} (x64/x32/arm64).
  url_handler = {
    versions_url = "https://api.github.com/repos/nim-lang/Nim/releases",
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://nim-lang.org/download/nim-{{version}}_{{nim_os}}_{{nim_arch}}.tar.xz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "nim-{{version}}_linux_x64.tar.xz", archive_format = 'TarXz },
      { platform = 'LinuxArm64, archive_name_template = "nim-{{version}}_linux_arm64.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinAmd64, archive_name_template = "nim-{{version}}_macos_x64.tar.xz", archive_format = 'TarXz },
      { platform = 'DarwinArm64, archive_name_template = "nim-{{version}}_macos_arm64.tar.xz", archive_format = 'TarXz },
    ],
    strip_components = 1,
  },
  executables = ["nim", "nimble", "nimsuggest"],
  health_check = "nim --version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["nim"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
