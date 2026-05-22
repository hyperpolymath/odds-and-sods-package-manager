# SPDX-License-Identifier: MPL-2.0
# Adjust — accessibility and digital justice runner
#
# Pairs with: Adjustfile.a2ml (same directory)
# Verb:       adjust
# Semantics:  every declared accessibility invariant must hold. Runner
#             checks WCAG 2.2 AA compliance, CLI colour-only signalling,
#             and i18n requirements. Hard gate on any regression.
#             ADJUST invariants are a subset of MUST — any ADJUST violation
#             is also a MUST violation.
# CLI:        `contractile adjust check`  → list invariants + compliance status
#             `contractile adjust audit`  → run accessibility audit tools
#
# Anything else in this directory is human-only notes/archive; machines ignore.
# See: docs/CONTRACTILE-SPEC.adoc

{
  pedigree = {
    contractile_verb = "adjust",
    semantics = "accessibility + digital justice enforcement",
    security = {
      leash = 'Leash,
      trust_level = "read-only audit; no write access",
      allow_network = true,               # may call axe-core, pa11y, or remote validators
      allow_filesystem_write = false,
      allow_subprocess = true,
      network_allowlist = ["localhost"],
    },
    metadata = {
      name = "adjust-runner",
      version = "1.0.0",
      description = "Enforces WCAG 2.2 AA and CLI accessibility invariants. Any regression blocks merge — accessibility is structural, not optional polish.",
      paired_xfile = "Adjustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    accessibility_invariants
      | Array {
          id | String,
          description | String,
          category | [| 'visual, 'keyboard, 'screen_reader, 'interactive, 'media, 'motion, 'cli_tui, 'documentation, 'i18n |],
          standard | String | default = "WCAG-2.2-AA",
          check_command | String,         # command that verifies invariant (exit 0 = compliant)
          status | [| 'declared, 'passing, 'failing, 'exempt |] | default = 'declared,
          notes | String | optional,
        },
  },

  run = {
    on_any_fail = "exit-nonzero",         # accessibility regression blocks merge
    report_format = "a2ml",
    emit_summary = true,
    minimum_standard = "WCAG-2.2-AA",
    encourage_aaa = true,
  },
}
