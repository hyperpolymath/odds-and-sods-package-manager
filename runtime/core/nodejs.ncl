# SPDX-License-Identifier: MPL-2.0
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "nodejs",
  description = "nodejs — JavaScript runtime built on V8",
  repository = "https://github.com/nodejs/node",
  homepage = "https://nodejs.org",
  version_source = 'CustomUrl,
  # version_pattern strips the "v" prefix Node uses in its dist index
  version_pattern = "^v([0-9]+\\.[0-9]+\\.[0-9]+)$",

  # UrlHandler.Nodejs maps platform → {{node_os}} (linux/darwin/win), {{node_arch}} (x64/arm64)
  url_handler = {
    versions_url = "https://nodejs.org/dist/index.json",
    version_key_pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://nodejs.org/dist/v{{version}}/node-v{{version}}-{{node_os}}-{{node_arch}}.tar.gz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "node-v{{version}}-linux-x64.tar.gz", archive_format = 'TarGz },
      { platform = 'LinuxArm64, archive_name_template = "node-v{{version}}-linux-arm64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinAmd64, archive_name_template = "node-v{{version}}-darwin-x64.tar.gz", archive_format = 'TarGz },
      { platform = 'DarwinArm64, archive_name_template = "node-v{{version}}-darwin-arm64.tar.gz", archive_format = 'TarGz },
    ],
    strip_components = 1,
  },
  executables = ["node", "npm", "npx"],
  health_check = "node --version",
  facets = { function = ['Runtime], ecosystem = ["javascript", "node"], usage = ['Interactive, 'Daemon], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
