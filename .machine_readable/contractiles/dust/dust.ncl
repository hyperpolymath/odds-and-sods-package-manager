# SPDX-License-Identifier: PMPL-1.0-or-later
# Dust — cleanup and hygiene runner
#
# Pairs with: Dustfile.a2ml (same directory)
# Verb:       dust
# Semantics:  everything declared as needing periodic cleanup must be
#             cleaned up on schedule. Runner checks for stale branches,
#             aged artefacts, and dead code past their retention window.
#             Hard gate if any retention policy is breached.
# CLI:        `contractile dust check`  → list items past retention deadline
#             `contractile dust sweep`  → execute declared cleanup actions
#
# Anything else in this directory is human-only notes/archive; machines ignore.
# See: docs/CONTRACTILE-SPEC.adoc

{
  pedigree = {
    contractile_verb = "dust",
    semantics = "cleanup + hygiene",
    security = {
      leash = 'Kennel,
      trust_level = "scheduled cleanup; read-write on declared targets only",
      allow_network = false,
      allow_filesystem_write = true,      # sweeps delete stale artefacts
      allow_subprocess = true,
      scope = "declared-cleanup-targets-only",
    },
    metadata = {
      name = "dust-runner",
      version = "1.0.0",
      description = "Checks and enforces cleanup schedules. Hard-gates on any retention-policy breach.",
      paired_xfile = "Dustfile.a2ml",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  schema = {
    cleanup_targets
      | Array {
          id | String,
          description | String,
          category | [| 'stale_branch, 'artefact, 'cache, 'dead_code, 'todo |],
          retention_days | Number,
          sweep_command | String,          # command that performs the cleanup
          check_command | String,          # command that reports what is overdue (exit 0 = clean)
          status | [| 'scheduled, 'overdue, 'swept, 'exempt |] | default = 'scheduled,
          notes | String | optional,
        },
  },

  run = {
    on_any_fail = "exit-nonzero",         # retention breach blocks merge
    report_format = "a2ml",
    emit_summary = true,
    require_backup_before_destructive = true,
  },
}
