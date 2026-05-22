# SPDX-License-Identifier: MPL-2.0
# Intend — purpose and scope runner
#
# Pairs with: Intentfile.a2ml (same directory)
# Verb:       intend
# Semantics:  validates that proposed changes stay within the declared
#             purpose and do not violate anti-purpose constraints.
#             Runner checks for scope creep, reversed architectural decisions,
#             and features that belong in a different repository.
# CLI:        `contractile intend check`    → report drift from declared purpose
#             `contractile intend validate` → verify architectural invariants
#
# Anything else in this directory is human-only notes/archive; machines ignore.
# See: docs/CONTRACTILE-SPEC.adoc

{
  pedigree = {
    contractile_verb = "intend",
    semantics = "purpose + scope validation",
    security = {
      leash = 'Leash,
      trust_level = "read-only analysis; no write access",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
    },
    metadata = {
      name = "intend-runner",
      version = "1.0.0",
      description = "Validates that changes respect declared purpose, anti-purpose, and architectural invariants. Flags scope creep and reversed decisions.",
      paired_xfile = "Intentfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    purpose_checks
      | Array {
          id | String,
          description | String,
          category | [| 'in_scope, 'out_of_scope, 'architectural_invariant, 'ecosystem_boundary |],
          check_command | String,         # command that verifies scope compliance
          status | [| 'declared, 'passing, 'failing, 'warn |] | default = 'declared,
          notes | String | optional,
        },
  },

  run = {
    on_any_fail = "warn",                 # scope drift warns; architectural reversals block
    on_architectural_violation = "exit-nonzero",
    report_format = "a2ml",
    emit_summary = true,
    wishes_included = true,               # intend ⊃ wishes (north-star aspirations)
  },
}
