# SPDX-License-Identifier: MPL-2.0
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "lefthook",
  description = "lefthook — Fast and powerful Git hooks manager",
  repository = "https://github.com/evilmartians/lefthook",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "lefthook_{{version}}_Linux_x86_64", archive_format = 'RawBinary },
      { platform = 'LinuxArm64, archive_name_template = "lefthook_{{version}}_Linux_arm64", archive_format = 'RawBinary },
      { platform = 'DarwinAmd64, archive_name_template = "lefthook_{{version}}_MacOS_x86_64", archive_format = 'RawBinary },
      { platform = 'DarwinArm64, archive_name_template = "lefthook_{{version}}_MacOS_arm64", archive_format = 'RawBinary },
    ],
    strip_components = 0,
  },
  executables = ["lefthook"],
  health_check = "lefthook version",
  facets = { function = ['CLI, 'BuildTool], ecosystem = ["git"], usage = ['Oneshot], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
