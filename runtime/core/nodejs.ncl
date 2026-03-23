# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "nodejs",
  description = "nodejs — JavaScript runtime built on V8",
  repository = "https://github.com/nodejs/node",
  homepage = "https://nodejs.org",
  version_source = 'CustomApi,
  install = { strategy = 'PrebuiltBinary, strip_components = 1 },
  executables = ["node", "npm", "npx"],
  health_check = "node --version",
  facets = { function = ['Runtime], ecosystem = ["javascript", "node"], usage = ['Interactive, 'Daemon], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
