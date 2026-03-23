# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "nim",
  description = "nim — Efficient, expressive, elegant systems language",
  repository = "https://github.com/nim-lang/Nim",
  homepage = "https://nim-lang.org",
  version_source = 'GitHubReleases,
  install = { strategy = 'PrebuiltBinary, strip_components = 1 },
  executables = ["nim", "nimble", "nimsuggest"],
  health_check = "nim --version",
  facets = { function = ['Compiler, 'Runtime], ecosystem = ["nim"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
