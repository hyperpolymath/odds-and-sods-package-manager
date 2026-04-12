# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Elixir source-build plugin.
# Replaces asdf-elixir.  Elixir compiles to BEAM bytecode — requires Erlang.

{
  name = "elixir",
  description = "Elixir — functional, concurrent language on the BEAM VM",
  repository = "https://github.com/elixir-lang/elixir",
  homepage = "https://elixir-lang.org",

  version_source = 'GitHubReleases,
  version_pattern = "^v([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  install = {
    strategy = 'BuildFromSource,
    build_steps = [
      "make",
      "make install PREFIX={{install_dir}}",
    ],
  },

  executables = ["elixir", "elixirc", "iex", "mix"],
  health_check = "elixir --version",

  system_dependencies = [
    {
      name = "erlang",
      check_command = "erl -eval 'halt().' -noshell",
      apt = "erlang",
      dnf = "erlang",
      pacman = "erlang",
      brew = "erlang",
      apk = "erlang",
    },
  ],

  facets = {
    function = ['Runtime, 'Compiler],
    ecosystem = ["beam", "elixir"],
    usage = ['Interactive, 'Batch, 'Daemon],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/asdf-vm/asdf-elixir",
  license = "PMPL-1.0-or-later",
  schema_version = "1.0.0",
}
