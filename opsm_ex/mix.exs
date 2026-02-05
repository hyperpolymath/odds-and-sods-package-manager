# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.MixProject do
  use Mix.Project

  def project do
    [
      app: :opsm,
      version: "1.0.1",
      elixir: "~> 1.14",
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
      {:toml, "~> 0.7"},
      {:optimus, "~> 0.5"},
      {:jason, "~> 1.4"},
      # Temporarily disabled - has multiple compilation errors (SafeColor guards, SafeCurrency abs/1)
      # TODO: Create PR to hyperpolymath/proven with fixes
      # {:proven, git: "https://github.com/hyperpolymath/proven.git", subdir: "bindings/elixir"},
      {:stream_data, "~> 0.6", only: :test},
      {:plug, "~> 1.15"},
      {:bandit, "~> 1.5"},
      # v1.0.1 Security primitives (SECURITY-STANDARDS.scm Phase 1)
      {:argon2_elixir, "~> 4.0"}
      # Note: BLAKE2b from :crypto module (built-in, no dependency needed)
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
    OPSM (Odds and Sods Package Manager) - Universal multi-language package manager with cryptographic trust verification.

    Supports 8 ecosystems (npm, Hex, Crates, PyPI, Nimble, Idris2, Git, Agentic) with
    built-in cryptographic primitives (Argon2id, ChaCha20-Poly1305, BLAKE2b, SHA3-512),
    trust pipeline, PubGrub dependency resolution, HAR-based discovery for obscure
    packages, and federation support. Includes formal security guarantees (SSRF prevention,
    JSON DoS protection, Result monad, lockfile integrity, encrypted API key storage).
    Post-quantum cryptography roadmap (Dilithium5, Kyber-1024, SPHINCS+).

    Keywords: package-manager, multi-language, cryptography, security, trust-verification,
    federated, elixir, argon2id, chacha20-poly1305, post-quantum, dependency-resolution
    """
  end

  defp package do
    [
      name: "opsm",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md),
      licenses: ["PMPL-1.0-or-later"],
      links: %{
        "GitHub" => "https://github.com/hyperpolymath/odds-and-sods-package-manager",
        "Docs" => "https://github.com/hyperpolymath/odds-and-sods-package-manager#readme",
        "Roadmap" => "https://github.com/hyperpolymath/odds-and-sods-package-manager/blob/main/ROADMAP.adoc",
        "Changelog" => "https://github.com/hyperpolymath/odds-and-sods-package-manager/releases"
      },
      maintainers: ["Jonathan D.A. Jewell <jonathan.jewell@open.ac.uk>"]
    ]
  end
end
