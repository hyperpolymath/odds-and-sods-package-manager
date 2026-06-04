# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.MixProject do
  use Mix.Project

  def project do
    [
      app: :opsm,
      version: "2.0.0",
      # Requires Elixir 1.16+ (OTP 26+). Tested on Elixir 1.19.5 / OTP 28.
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      aliases: aliases(),
      description: description(),
      package: package(),
      name: "OPSM",
      source_url: "https://github.com/hyperpolymath/odds-and-sods-package-manager"
    ]
  end

  def application do
    [
      mod: {Opsm.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:castore, "~> 1.0"},
      {:toml, "~> 0.7"},
      {:optimus, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:proven, git: "https://github.com/hyperpolymath/proven.git", subdir: "bindings/elixir"},
      {:verisim_client, git: "https://github.com/hyperpolymath/verisimdb.git", sparse: "connectors/clients/elixir"},
      {:stream_data, "~> 0.6", only: :test},
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.5"},
      # v1.0.1 Security primitives (SECURITY-STANDARDS.scm Phase 1)
      {:argon2_elixir, "~> 4.0"},
      # Note: BLAKE2b from :crypto module (built-in, no dependency needed)
      # Note: Rustler Elixir dep NOT needed — NIF loaded via @on_load :erlang.load_nif/2
      # The Rust crate `rustler` is a Cargo dependency in native/opsm_pq_nif/Cargo.toml
      # Build with: cd native/opsm_pq_nif && cargo build --release
      # Then copy: cp target/release/libopsm_pq_nif.so priv/native/libopsm_pq_nif.so
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp escript do
    [
      main_module: Opsm.CLI,
      name: :opsm
    ]
  end

  defp aliases do
    [
      build_cli: ["deps.get", "escript.build"]
    ]
  end

  defp description do
    """
    Universal package manager with cryptographic security (Argon2id, ChaCha20-Poly1305, SHA3-512).
    Supports 8 ecosystems with trust verification, PubGrub resolution, and formal security guarantees.
    """
  end

  defp package do
    [
      name: "opsm",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["MPL-2.0"],
      links: %{
        "GitHub" => "https://github.com/hyperpolymath/odds-and-sods-package-manager",
        "Docs" => "https://github.com/hyperpolymath/odds-and-sods-package-manager#readme",
        "Roadmap" => "https://github.com/hyperpolymath/odds-and-sods-package-manager/blob/main/ROADMAP.adoc",
        "Changelog" => "https://github.com/hyperpolymath/odds-and-sods-package-manager/releases"
      },
      maintainers: ["Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>"]
    ]
  end
end
