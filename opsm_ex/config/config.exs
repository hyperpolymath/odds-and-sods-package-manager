# SPDX-License-Identifier: MPL-2.0
import Config

# Suppress noisy Bandit startup logs in CLI mode
config :logger, level: :warning

# VeriSimDB instance for OPSM event persistence
# Port 6077 — dedicated instance, graceful degradation if unreachable
config :opsm, :verisimdb,
  base_url: System.get_env("OPSM_VERISIMDB_URL", "http://127.0.0.1:6077"),
  enabled: System.get_env("OPSM_VERISIMDB_ENABLED", "true") != "false",
  timeout: 5_000
