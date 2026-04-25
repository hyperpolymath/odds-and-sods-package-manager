# SPDX-License-Identifier: PMPL-1.0-or-later
# Trust — integrity and provenance runner
#
# Pairs with: Trustfile.a2ml (same directory)
# Verb:       trust
# Semantics:  every declared trust assertion (provenance, signing, licence audit,
#             SHA-pinning) must be verified before merge. Runner checks supply
#             chain, dependency provenance, and signing posture.
#             Hard gate on any unmet trust assertion.
# CLI:        `contractile trust check`  → list assertions + verification status
#             `contractile trust verify` → run all verification probes
#
# Anything else in this directory is human-only notes/archive; machines ignore.
# See: docs/CONTRACTILE-SPEC.adoc

{
  pedigree = {
    contractile_verb = "trust",
    semantics = "integrity + provenance verification",
    security = {
      leash = 'Leash,
      trust_level = "read-only verification; no write access except reporting",
      allow_network = true,               # provenance checks may hit registries
      allow_filesystem_write = false,
      allow_subprocess = true,
      network_allowlist = ["api.github.com", "registry.npmjs.org", "crates.io"],
    },
    metadata = {
      name = "trust-runner",
      version = "1.0.0",
      description = "Verifies supply-chain trust assertions: provenance, signing, SHA-pinning, licence compliance. Hard-gates on any unmet assertion.",
      paired_xfile = "Trustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    trust_assertions
      | Array {
          id | String,
          description | String,
          category | [| 'provenance, 'signing, 'licence, 'sha_pinning, 'spdx, 'reproducible |],
          verify_command | String,        # command that verifies the assertion (exit 0 = trusted)
          status | [| 'declared, 'verified, 'failing, 'exempt |] | default = 'declared,
          notes | String | optional,
        },
  },

  run = {
    on_any_fail = "exit-nonzero",         # unmet trust assertion blocks merge
    report_format = "a2ml",
    emit_summary = true,
    cache_results = false,                # always re-verify; no stale trust cache
  },
}
