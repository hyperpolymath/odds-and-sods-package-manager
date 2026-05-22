# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Rust toolchain plugin — delegates to rustup.
# "Rust" always means "Rust/SPARK" in the hyperpolymath estate.
# New Rust projects are designed to admit SPARK/Ada modules via Idris2-ABI + Zig-FFI.

{
  name = "rust",
  description = "Rust/SPARK toolchain — systems language, primary CLI and WASM target (always with SPARK potential)",
  repository = "https://github.com/rust-lang/rust",
  homepage = "https://www.rust-lang.org",

  version_source = 'CustomUrl,
  version_pattern = "^(stable|nightly|beta|[0-9]+\\.[0-9]+\\.[0-9]+)$",
  version_sort = 'Semver,

  url_handler = {
    # rustup manages Rust versions — OPSM delegates to it
    versions_url = "https://static.rust-lang.org/dist/channel-rust-stable.toml",
    version_key_pattern = "^(stable|nightly|beta|[0-9]+\\.[0-9]+\\.[0-9]+)$",
    archive_url_template = "https://static.rust-lang.org/dist/rust-{{version}}-{{rust_triple}}.tar.gz",
  },

  install = {
    # Delegate to rustup — it handles toolchain management far better than direct installs
    strategy = 'DelegateToManager,
    delegate_to = "rustup",
    delegate_install_command = "rustup toolchain install {{version}} --profile minimal",
  },

  executables = ["rustc", "cargo", "rustup", "rustfmt", "clippy-driver", "rust-analyzer"],
  health_check = "rustc --version",

  system_dependencies = [
    {
      name = "rustup",
      check_command = "rustup --version",
      apt = "rustup",
      dnf = "rustup",
      brew = "rustup-init",
      apk = "rustup",
      pacman = "rustup",
    },
  ],

  environment = [
    {
      variable = "CARGO_HOME",
      value_template = "{{opsm_runtime_dir}}/rust/{{version}}/.cargo",
    },
    {
      variable = "RUSTUP_HOME",
      value_template = "{{opsm_runtime_dir}}/rust/{{version}}/.rustup",
    },
  ],

  facets = {
    function = ['Compiler, 'Runtime, 'BuildTool],
    ecosystem = ["rust", "systems", "wasm"],
    usage = ['Batch, 'Oneshot],
    tier = 'Core,
  },

  asdf_origin = "https://github.com/asdf-community/asdf-rust",
  license = "MPL-2.0",
  schema_version = "1.0.0",
}
