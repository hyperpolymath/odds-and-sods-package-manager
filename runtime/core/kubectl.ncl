# SPDX-License-Identifier: MPL-2.0
let RuntimePlugin = import "../contract/runtime-plugin.ncl" in
{
  name = "kubectl",
  description = "kubectl — Kubernetes command-line tool",
  repository = "https://github.com/kubernetes/kubectl",
  homepage = "https://kubernetes.io/docs/reference/kubectl/",
  # kubectl versions tracked from kubernetes/kubectl GitHub releases (match k8s version scheme)
  version_source = 'GitHubReleases,
  # Tags have v-prefix; extract the raw semver
  version_pattern = "^v([0-9]+\\.[0-9]+\\.[0-9]+)$",

  # Binaries served from dl.k8s.io, not GitHub release assets.
  # UrlHandler.Kubectl maps platform → {{kubectl_os}} (linux/darwin/windows), {{kubectl_arch}} (amd64/arm64)
  url_handler = {
    versions_url = "https://api.github.com/repos/kubernetes/kubectl/releases",
    version_key_pattern = "^v[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://dl.k8s.io/release/v{{version}}/bin/{{kubectl_os}}/{{kubectl_arch}}/kubectl",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      { platform = 'LinuxAmd64, archive_name_template = "kubectl", archive_format = 'RawBinary },
      { platform = 'LinuxArm64, archive_name_template = "kubectl", archive_format = 'RawBinary },
      { platform = 'DarwinAmd64, archive_name_template = "kubectl", archive_format = 'RawBinary },
      { platform = 'DarwinArm64, archive_name_template = "kubectl", archive_format = 'RawBinary },
    ],
    strip_components = 0,
  },
  executables = ["kubectl"],
  health_check = "kubectl version --client",
  facets = { function = ['CLI, 'ContainerTool], ecosystem = ["kubernetes"], usage = ['Interactive], tier = 'Core },
  schema_version = "1.0.0",
} | RuntimePlugin
