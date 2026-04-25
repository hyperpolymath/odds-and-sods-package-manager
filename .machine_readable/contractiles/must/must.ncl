# SPDX-License-Identifier: PMPL-1.0-or-later
# Must — hard-constraint enforcement runner
#
# Pairs with: Mustfile.a2ml (same directory)
# Verb:       must
# Semantics:  every declared invariant must hold at all times. Runner
#             machine-checks each MUST constraint and hard-gates on any
#             violation. There are no soft MUSTs — all violations block merge.
# CLI:        `contractile must check`  → list invariants + current status
#             `contractile must enforce` → run all constraint checks
#
# Anything else in this directory is human-only notes/archive; machines ignore.
# See: docs/CONTRACTILE-SPEC.adoc

{
  pedigree = {
    contractile_verb = "must",
    semantics = "hard-constraint enforcement",
    security = {
      leash = 'Leash,
      trust_level = "read-only structural checks; no write access",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = true,
    },
    metadata = {
      name = "must-runner",
      version = "1.0.0",
      description = "Machine-checks all declared MUST invariants. Any violation blocks merge — no exceptions.",
      paired_xfile = "Mustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    invariants
      | Array {
          id | String,
          description | String,
          category | [| 'path, 'language_policy, 'dangerous_pattern, 'licence, 'structure, 'ci, 'quality, 'abi_ffi |],
          check_command | String,         # command that verifies invariant holds (exit 0 = ok)
          status | [| 'declared, 'passing, 'failing |] | default = 'declared,
          notes | String | optional,
        },
  },

  run = {
    on_any_fail = "exit-nonzero",         # all invariant violations block merge
    report_format = "a2ml",
    emit_summary = true,
    trust_override_allowed = false,       # even max-trust agents cannot bypass MUST
  },
}
