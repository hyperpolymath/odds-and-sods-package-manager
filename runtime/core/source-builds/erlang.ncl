# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Erlang/OTP source-build plugin.
# Replaces asdf-erlang.  Builds from source via kerl or direct configure/make.

{
  name = "erlang",
  description = "Erlang/OTP — fault-tolerant, distributed, BEAM runtime",
  repository = "https://github.com/erlang/otp",
  homepage = "https://www.erlang.org",

  version_source = 'GitHubReleases,
  version_pattern = "^OTP-([0-9]+\\.[0-9]+(\\.[0-9]+)?)$",
  version_sort = 'Semver,

  install = {
    strategy = 'BuildFromSource,
    build_steps = [
      "./otp_build autoconf",
      "./configure --prefix={{install_dir}} --with-ssl --enable-dynamic-ssl-lib",
      "make -j$(nproc)",
      "make install",
    ],
    configure_flags = [
      "--enable-kernel-poll",
      "--enable-threads",
      "--enable-smp-support",
      "--enable-hipe",
    ],
  },

  executables = ["erl", "erlc", "rebar3", "escript"],
  health_check = "erl -eval 'io:format(erlang:system_info(otp_release)), halt().' -noshell",

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
      name = "ncurses",
      check_command = "ncurses6-config --version",
      apt = "libncurses5-dev libncursesw5-dev",
      dnf = "ncurses-devel",
      pacman = "ncurses",
      brew = "ncurses",
      apk = "ncurses-dev",
    },
    {
      name = "autoconf",
      check_command = "autoconf --version",
      apt = "autoconf",
      dnf = "autoconf",
      pacman = "autoconf",
      brew = "autoconf",
      apk = "autoconf",
    },
  ],

  facets = {
    function = ['Runtime, 'Compiler],
    ecosystem = ["beam", "erlang"],
    usage = ['Interactive, 'Batch, 'Daemon],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/asdf-vm/asdf-erlang",
  license = "PMPL-1.0-or-later",
  schema_version = "1.0.0",
}
