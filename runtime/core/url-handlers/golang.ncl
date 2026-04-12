# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Go (golang) runtime plugin — custom URL handler for golang.org/dl.
# Replaces asdf-golang.  Version list from https://go.dev/dl/?mode=json&include=all.
# Note: Go is BANNED as a development language (use Rust instead).
# This plugin is ONLY for running Go tools that have no Rust/Zig alternative.

{
  name = "golang",
  description = "Go runtime — TOOL USE ONLY. Go is banned as a development language; use Rust.",
  repository = "https://github.com/golang/go",
  homepage = "https://go.dev",

  version_source = 'CustomUrl,
  version_pattern = "^go([0-9]+\\.[0-9]+(\\.[0-9]+)?)$",
  version_sort = 'Semver,

  url_handler = {
    versions_url = "https://go.dev/dl/?mode=json&include=all",
    # Response is a JSON array; each element has "version" field like "go1.21.0"
    version_key_pattern = "^go[0-9]+\\.[0-9]+\\.[0-9]+$",
    archive_url_template = "https://go.dev/dl/{{go_version}}.{{go_os}}-{{go_arch}}.tar.gz",
  },

  install = {
    strategy = 'PrebuiltBinary,
    platforms = [
      {
        platform = 'LinuxAmd64,
        archive_name_template = "go{{version}}.linux-amd64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'LinuxArm64,
        archive_name_template = "go{{version}}.linux-arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinAmd64,
        archive_name_template = "go{{version}}.darwin-amd64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'DarwinArm64,
        archive_name_template = "go{{version}}.darwin-arm64.tar.gz",
        archive_format = 'TarGz,
      },
      {
        platform = 'WindowsAmd64,
        archive_name_template = "go{{version}}.windows-amd64.zip",
        archive_format = 'Zip,
      },
    ],
    # Go archive unpacks to a "go/" directory — strip that
    strip_components = 1,
    subdirectory = "go",
  },

  executables = ["go", "gofmt"],
  health_check = "go version",

  facets = {
    function = ['Runtime, 'Compiler, 'BuildTool],
    ecosystem = ["go"],
    usage = ['Batch, 'Oneshot],
    # Tier is Upstream — not a hyperpolymath ecosystem language
    tier = 'Upstream,
  },

  asdf_origin = "https://github.com/kennyp/asdf-golang",
  license = "PMPL-1.0-or-later",
  schema_version = "1.0.0",
}
