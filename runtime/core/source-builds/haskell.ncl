# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Haskell (GHC) source-build plugin.
# Replaces asdf-haskell.  Uses ghcup under the hood for managed installs.
# GHC is used for: Scaffoldia CLI, k9-haskell, pandoc-k9, pandoc-a2ml.

{
  name = "haskell",
  description = "GHC Haskell compiler — used for Scaffoldia, k9-haskell, pandoc tools",
  repository = "https://github.com/ghc/ghc",
  homepage = "https://www.haskell.org/ghc",

  version_source = 'CustomUrl,
  version_pattern = "^([0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  url_handler = {
    versions_url = "https://www.haskell.org/ghc/download.html",
    # Delegate version listing to ghcup: `ghcup list -t ghc -r`
    version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+(\\.[0-9]+)?$",
    # ghcup downloads GHC from downloads.haskell.org
    archive_url_template = "https://downloads.haskell.org/ghc/{{version}}/ghc-{{version}}-{{ghc_arch}}-{{ghc_os}}-linux.tar.xz",
  },

  install = {
    # Use ghcup as the delegate manager — it handles GHC build/install
    strategy = 'DelegateToManager,
    delegate_to = "ghcup",
    delegate_install_command = "ghcup install ghc {{version}} --set",

    # Fallback build from source if ghcup unavailable
    build_steps = [
      "./boot",
      "./configure --prefix={{install_dir}}",
      "make -j$(nproc)",
      "make install",
    ],
  },

  executables = ["ghc", "ghci", "cabal", "stack", "runghc", "runhaskell"],
  health_check = "ghc --version",

  system_dependencies = [
    {
      name = "ghcup",
      check_command = "ghcup --version",
      apt = "ghcup",
      dnf = "ghcup",
      brew = "ghcup",
      apk = "ghcup",
      pacman = "ghcup",
    },
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
    ecosystem = ["haskell"],
    usage = ['Batch, 'Interactive],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/vic/asdf-haskell",
  license = "PMPL-1.0-or-later",
  schema_version = "1.0.0",
}
