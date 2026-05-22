# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Ruby source-build plugin.
# Ruby is used for: Jekyll GitHub Pages workflows, some tooling.

{
  name = "ruby",
  description = "Ruby — used for Jekyll/GitHub Pages CI workflows and legacy tooling",
  repository = "https://github.com/ruby/ruby",
  homepage = "https://www.ruby-lang.org",

  version_source = 'GitHubReleases,
  version_pattern = "^v([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  install = {
    strategy = 'BuildFromSource,
    build_steps = [
      "./configure --prefix={{install_dir}} --enable-shared --disable-install-doc",
      "make -j$(nproc)",
      "make install",
    ],
    configure_flags = [
      "--with-openssl-dir=$(brew --prefix openssl 2>/dev/null || echo /usr)",
    ],
  },

  executables = ["ruby", "gem", "bundle", "irb", "rake", "erb"],
  health_check = "ruby --version",

  legacy_files = {
    filenames = [".ruby-version"],
  },

  system_dependencies = [
    {
      name = "openssl",
      check_command = "openssl version",
      apt = "libssl-dev",
      dnf = "openssl-devel",
      pacman = "openssl",
      brew = "openssl",
      apk = "openssl-dev",
    },
    {
      name = "readline",
      check_command = "echo 'require \"readline\"' | ruby",
      apt = "libreadline-dev",
      dnf = "readline-devel",
      pacman = "readline",
      brew = "readline",
      apk = "readline-dev",
    },
  ],

  facets = {
    function = ['Runtime, 'Compiler],
    ecosystem = ["ruby"],
    usage = ['Interactive, 'Batch],
    tier = 'Upstream,
  },

  asdf_origin = "https://github.com/asdf-vm/asdf-ruby",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
