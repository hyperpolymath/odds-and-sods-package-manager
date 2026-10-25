# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
#
# ExUnit bootstrap.
#
# Excluded by default:
#   :e2e           — needs the full package pipeline (see .github/workflows/e2e.yml)
#   :external_api  — hits live registry/version APIs
#   :requires_nif  — needs opsm_pq_nif built (see .github/workflows/nif-build.yml)
#   :live_service  — needs the trust services from selur-compose.yml
#   :live_download — performs real tool installs
#
# OPSM_PROVEN_REPORT=1 (set in .github/workflows/ci.yml) attaches the
# Proven-Tests reporter. It only observes; it cannot change a test result.
exclude = [:e2e, :external_api, :requires_nif, :live_service, :live_download]

if System.get_env("OPSM_PROVEN_REPORT") == "1" do
  Code.require_file("support/proven_reporter.ex", __DIR__)
  # `formatters`, not `event_managers`. ExUnit 1.19 has no `:event_managers`
  # option (that is the name of its internal module, ExUnit.EventManager), and
  # an unknown key in ExUnit.start/1 is silently ignored — so the reporter was
  # never started, the report was never written, and every downstream step
  # looked merely "quiet". Listing the formatter replaces the default, so
  # ExUnit.CLIFormatter has to be named again or the suite prints nothing.
  ExUnit.start(exclude: exclude, formatters: [ExUnit.CLIFormatter, Opsm.ProvenReporter])
else
  ExUnit.start(exclude: exclude)
end
