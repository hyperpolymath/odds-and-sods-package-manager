# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Julia runtime plugin — custom URL handler for julialang.org S3 downloads.
# Replaces the asdf-julia plugin.  Julia releases are on AWS S3 via
# https://julialang-s3.julialang.org/ and versions are listed via
# https://julialang-s3.julialang.org/bin/versions.json.

{
  name = "julia",
  description = "Julia scientific computing language — dynamic, high-performance, multiple dispatch",
  repository = "https://github.com/JuliaLang/julia",
  homepage = "https://julialang.org",

  version_source = 'CustomUrl,
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  url_handler = {
    versions_url = "https://julialang-s3.julialang.org/bin/versions.json",
    # JSON response is an object keyed by version string; filter to stable releases
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://julialang-s3.julialang.org/bin/{{julia_os}}/{{julia_arch}}/{{julia_minor}}/julia-{{version}}-{{julia_os}}{{julia_arch_suffix}}.tar.gz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "julia-{{version}}-linux-x86_64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "julia-{{version}}-linux-aarch64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "julia-{{version}}-mac64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "julia-{{version}}-macaarch64.tar.gz",
        archive_format = 'TarGz,
      },
    ],
    strip_components = 1,
    subdirectory = "julia-{{version}}",
  },

  executables = ["julia"],
  health_check = "julia --version",

  facets = {
    function = ['Runtime, 'Compiler, 'Runtime],
    ecosystem = ["julia", "scientific", "data"],
    usage = ['Interactive, 'Batch],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/asdf-community/asdf-julia",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
