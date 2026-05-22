# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# OCaml source-build plugin.
# OCaml is used for: AffineScript compiler, ephapax (epx CLI).

{
  name = "ocaml",
  description = "OCaml compiler — used for AffineScript compiler and Ephapax tooling",
  repository = "https://github.com/ocaml/ocaml",
  homepage = "https://ocaml.org",

  version_source = 'GitHubReleases,
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  install = {
    # Delegate to opam — it handles OCaml switch management
    strategy = 'DelegateToManager,
    delegate_to = "opam",
    delegate_install_command = "opam switch create {{version}} --no-switch",

    # Fallback: build from source
    build_steps = [
      "./configure --prefix={{install_dir}}",
      "make world.opt",
      "make install",
    ],
  },

  executables = ["ocaml", "ocamlopt", "ocamlc", "ocamlfind", "opam", "dune"],
  health_check = "ocaml --version",

  system_dependencies = [
    {
      name = "build-essential",
      check_command = "gcc --version",
      apt = "build-essential",
      dnf = "gcc gcc-c++ make",
      pacman = "base-devel",
      brew = "gcc",
      apk = "build-base",
    },
  ],

  facets = {
    function = ['Compiler, 'Runtime],
    ecosystem = ["ocaml"],
    usage = ['Batch, 'Interactive],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/asdf-community/asdf-ocaml",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
