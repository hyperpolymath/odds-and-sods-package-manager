# SPDX-License-Identifier: PMPL-1.0-or-later
let { RuntimePlugin, .. } = import "../contract/runtime-plugin.ncl" in
{
  name = "kubectl",
  description = "kubectl — Kubernetes command-line tool",
  repository = "https://github.com/kubernetes/kubectl",
  homepage = "https://kubernetes.io/docs/reference/kubectl/",
  version_source = 'GitHubReleases,
  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "kubectl-linux-amd64", archive_format = 'RawBinary },
      { platform = 'LinuxArm64, archive_name_template = "kubectl-linux-arm64", archive_format = 'RawBinary },
      { platform = 'DarwinAmd64, archive_name_template = "kubectl-darwin-amd64", archive_format = 'RawBinary },
      { platform = 'DarwinArm64, archive_name_template = "kubectl-darwin-arm64", archive_format = 'RawBinary },
    ],
    strip_components = 0,
  },
  executables = ["kubectl"],
  health_check = "kubectl version --client",
  facets = { function = ['CLI, 'ContainerTool], ecosystem = ["kubernetes"], usage = ['Interactive], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
