# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Node.js runtime plugin — custom URL handler for nodejs.org.
# Replaces asdf-nodejs.  Version list from https://nodejs.org/dist/index.json.
# Note: Node.js is BANNED as a runtime for hyperpolymath code (use Deno).
# This plugin is ONLY for running legacy Node.js tools with no Deno equivalent.

{
  name = "nodejs",
  description = "Node.js runtime — LEGACY TOOL USE ONLY. Use Deno for all hyperpolymath JS/TS work.",
  repository = "https://github.com/nodejs/node",
  homepage = "https://nodejs.org",

  version_source = 'CustomUrl,
  version_pattern = "^v([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  url_handler = {
    versions_url = "https://nodejs.org/dist/index.json",
    # Array of objects; each has "version" field like "v21.6.0"
    version_key_pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://nodejs.org/dist/v{{version}}/node-v{{version}}-{{node_os}}-{{node_arch}}.tar.gz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "node-v{{version}}-linux-x64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "node-v{{version}}-linux-arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "node-v{{version}}-darwin-x64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "node-v{{version}}-darwin-arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'WindowsAmd64,
        archive_name_template = "node-v{{version}}-win-x64.zip",
        archive_format = 'Zip,
      },
    ],
    strip_components = 1,
  },

  executables = ["node", "npm", "npx"],
  health_check = "node --version",

  legacy_files = {
    filenames = [".nvmrc", ".node-version"],
  },

  facets = {
    function = ['Runtime],
    ecosystem = ["javascript"],
    usage = ['Interactive, 'Batch, 'Daemon],
    tier = 'Upstream,
  },

  asdf_origin = "https://github.com/asdf-vm/asdf-nodejs",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
