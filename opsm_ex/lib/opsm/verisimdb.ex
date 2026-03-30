# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule Opsm.VeriSimDB do
  @moduledoc """
  VeriSimDB integration for OPSM.

  Persists all install, uninstall, resolve, and trust events as octad entities
  in a dedicated VeriSimDB instance (port 6077). Every OPSM action that mutates
  package state is recorded here for auditability, drift detection, and Hypatia
  analytics.

  Degrades gracefully — if VeriSimDB is unreachable, operations log a warning
  and continue. OPSM never blocks on VeriSimDB unavailability.

  ## Octad Schema

  Each OPSM event maps to a VeriSimDB octad with these modalities:

    - **Document**: Human-readable event description (title, body, fields)
    - **Graph**: Relationships (package → registry, package → dependencies)
    - **Temporal**: Timestamp, version, actor
    - **Provenance**: Origin chain (registry → trust pipeline → install)
    - **Semantic**: Event type tags, category classification

  ## Configuration

  Set in `config/config.exs`:

      config :opsm, :verisimdb,
        base_url: "http://127.0.0.1:6077",
        enabled: true,
        timeout: 5_000

  Or via environment variables:

      OPSM_VERISIMDB_URL=http://127.0.0.1:6077
      OPSM_VERISIMDB_ENABLED=true
  """

  use GenServer
  require Logger

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Start the VeriSimDB client GenServer under the OPSM supervision tree.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record a package installation event.

  Persists the package name, version, registry (forth), scope, install path,
  checksum, linked binaries, trust result, and SLSA provenance as a single
  octad entity with full modality coverage.
  """
  @spec record_install(map()) :: :ok
  def record_install(event) do
    GenServer.cast(__MODULE__, {:record, :install, event})
  end

  @doc """
  Record a package removal event.

  Persists which package was removed, when, and any cleanup actions taken.
  """
  @spec record_uninstall(map()) :: :ok
  def record_uninstall(event) do
    GenServer.cast(__MODULE__, {:record, :uninstall, event})
  end

  @doc """
  Record a dependency resolution event.

  Persists the root dependency, resolved package graph, constraint decisions,
  and any backtracking that occurred.
  """
  @spec record_resolution(map()) :: :ok
  def record_resolution(event) do
    GenServer.cast(__MODULE__, {:record, :resolution, event})
  end

  @doc """
  Record a trust pipeline verification event.

  Persists the trust check outcome (passed/warning/failed), attestations,
  SLSA provenance, PQ signatures, and sustainability scores.
  """
  @spec record_trust_check(map()) :: :ok
  def record_trust_check(event) do
    GenServer.cast(__MODULE__, {:record, :trust_check, event})
  end

  @doc """
  Query installed packages via VQL-UT.

  Returns `{:ok, results}` or `{:error, reason}`.
  """
  @spec query(String.t()) :: {:ok, map()} | {:error, term()}
  def query(vql_query) do
    GenServer.call(__MODULE__, {:query, vql_query}, 10_000)
  end

  @doc """
  Check if VeriSimDB is reachable.
  """
  @spec healthy?() :: boolean()
  def healthy? do
    GenServer.call(__MODULE__, :health, 5_000)
  catch
    :exit, _ -> false
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    config = load_config()

    if config.enabled do
      case VeriSimClient.new(config.base_url, timeout: config.timeout) do
        {:ok, client} ->
          Logger.info("[OPSM.VeriSimDB] Connected to #{config.base_url}")
          {:ok, %{client: client, config: config, connected: true}}

        {:error, reason} ->
          Logger.warning("[OPSM.VeriSimDB] Could not connect to #{config.base_url}: #{reason}")
          {:ok, %{client: nil, config: config, connected: false}}
      end
    else
      Logger.info("[OPSM.VeriSimDB] Disabled by configuration")
      {:ok, %{client: nil, config: config, connected: false}}
    end
  end

  @impl true
  def handle_cast({:record, event_type, _event}, %{connected: false} = state) do
    Logger.debug("[OPSM.VeriSimDB] Skipping #{event_type} record — not connected")
    {:noreply, maybe_reconnect(state)}
  end

  def handle_cast({:record, event_type, event}, %{client: client} = state) do
    octad = build_octad(event_type, event)

    case VeriSimClient.Octad.create(client, octad) do
      {:ok, _created} ->
        Logger.debug("[OPSM.VeriSimDB] Recorded #{event_type} for #{event[:name] || "unknown"}")
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[OPSM.VeriSimDB] Failed to record #{event_type}: #{inspect(reason)}")
        {:noreply, %{state | connected: false}}
    end
  end

  @impl true
  def handle_call({:query, _vql_query}, _from, %{connected: false} = state) do
    {:reply, {:error, :not_connected}, maybe_reconnect(state)}
  end

  def handle_call({:query, vql_query}, _from, %{client: client} = state) do
    case VeriSimClient.Vql.execute(client, vql_query) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:health, _from, %{client: nil} = state) do
    {:reply, false, state}
  end

  def handle_call(:health, _from, %{client: client} = state) do
    case VeriSimClient.health(client) do
      {:ok, true} -> {:reply, true, %{state | connected: true}}
      _ -> {:reply, false, %{state | connected: false}}
    end
  end

  # ---------------------------------------------------------------------------
  # Octad builders — one per event type
  # ---------------------------------------------------------------------------

  defp build_octad(:install, event) do
    %{
      name: "opsm:install:#{event[:name]}@#{event[:version]}",
      description: "Package install: #{event[:name]}@#{event[:version]} from @#{event[:forth]}",

      document: %{
        title: "Install #{event[:name]}@#{event[:version]}",
        body: """
        Package: #{event[:name]}
        Version: #{event[:version]}
        Registry: #{event[:forth]}
        Scope: #{event[:scope]}
        Path: #{event[:path]}
        Checksum: #{event[:checksum]}
        Linked binaries: #{inspect(event[:linked_bins] || [])}
        """,
        fields: %{
          event_type: "install",
          package: event[:name],
          version: event[:version],
          forth: to_string(event[:forth]),
          scope: to_string(event[:scope]),
          path: event[:path],
          checksum: event[:checksum],
          checksum_algo: to_string(event[:checksum_algo]),
          tarball_url: event[:tarball_url]
        }
      },

      graph: %{
        relationships:
          [%{predicate: "installed_from", target: "registry:#{event[:forth]}"}] ++
          Enum.map(event[:dependencies] || [], fn dep ->
            %{predicate: "depends_on", target: "package:#{dep}"}
          end)
      },

      temporal: %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        version: 1,
        author: "opsm-installer"
      },

      provenance: %{
        origin: "opsm:installer",
        chain: [
          "registry:#{event[:forth]}",
          "trust:#{event[:trust_result] || "unchecked"}",
          "install:#{event[:path]}"
        ],
        actors: ["opsm-cli"]
      },

      semantic: %{
        types: ["opsm:event:install", "opsm:package:#{event[:forth]}"],
        properties: %{
          slsa_level: event[:slsa_level],
          trust_status: to_string(event[:trust_result] || "unchecked"),
          sustainability_score: event[:sustainability_score]
        }
      }
    }
  end

  defp build_octad(:uninstall, event) do
    %{
      name: "opsm:uninstall:#{event[:name]}@#{event[:version]}",
      description: "Package removal: #{event[:name]}@#{event[:version]}",

      document: %{
        title: "Uninstall #{event[:name]}@#{event[:version]}",
        body: """
        Package: #{event[:name]}
        Version: #{event[:version]}
        Registry: #{event[:forth]}
        Removed path: #{event[:path]}
        Cleanup actions: #{length(event[:cleanup_actions] || [])}
        """,
        fields: %{
          event_type: "uninstall",
          package: event[:name],
          version: event[:version],
          forth: to_string(event[:forth])
        }
      },

      temporal: %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        version: 1,
        author: "opsm-installer"
      },

      provenance: %{
        origin: "opsm:installer",
        chain: ["uninstall:#{event[:name]}"],
        actors: ["opsm-cli"]
      },

      semantic: %{
        types: ["opsm:event:uninstall"],
        properties: %{}
      }
    }
  end

  defp build_octad(:resolution, event) do
    resolved_count = length(event[:resolved] || [])

    %{
      name: "opsm:resolve:#{event[:root_package]}",
      description: "Dependency resolution: #{event[:root_package]} → #{resolved_count} packages",

      document: %{
        title: "Resolve #{event[:root_package]}",
        body: """
        Root: #{event[:root_package]}@#{event[:root_constraint]}
        Registry: #{event[:forth]}
        Resolved: #{resolved_count} package(s)
        Backtrack count: #{event[:backtrack_count] || 0}
        """,
        fields: %{
          event_type: "resolution",
          root_package: event[:root_package],
          root_constraint: event[:root_constraint],
          forth: to_string(event[:forth]),
          resolved_count: resolved_count,
          resolved_packages: Enum.join(event[:resolved] || [], ", ")
        }
      },

      graph: %{
        relationships:
          Enum.map(event[:resolved] || [], fn pkg_name ->
            %{predicate: "resolved", target: "package:#{pkg_name}"}
          end)
      },

      temporal: %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        version: 1,
        author: "opsm-resolver"
      },

      provenance: %{
        origin: "opsm:resolver",
        chain: ["resolve:#{event[:root_package]}"],
        actors: ["opsm-cli"]
      },

      semantic: %{
        types: ["opsm:event:resolution"],
        properties: %{
          sustainability_preference: event[:sustainability_preference] || false
        }
      }
    }
  end

  defp build_octad(:trust_check, event) do
    %{
      name: "opsm:trust:#{event[:name]}@#{event[:version]}",
      description: "Trust check: #{event[:name]}@#{event[:version]} → #{event[:overall]}",

      document: %{
        title: "Trust #{event[:overall]}: #{event[:name]}@#{event[:version]}",
        body: """
        Package: #{event[:name]}
        Version: #{event[:version]}
        Overall: #{event[:overall]}
        Warnings: #{inspect(event[:warnings] || [])}
        Attestations: #{length(event[:attestations] || [])}
        SLSA level: #{event[:slsa_level]}
        PQ signed: #{event[:pq_signed] || false}
        """,
        fields: %{
          event_type: "trust_check",
          package: event[:name],
          version: event[:version],
          overall: to_string(event[:overall]),
          warning_count: length(event[:warnings] || []),
          attestation_count: length(event[:attestations] || []),
          slsa_level: event[:slsa_level],
          pq_signed: event[:pq_signed] || false
        }
      },

      temporal: %{
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        version: 1,
        author: "opsm-trust-pipeline"
      },

      provenance: %{
        origin: "opsm:trust-pipeline",
        chain: [
          "check:attestations",
          "check:license",
          "check:sustainability",
          "check:slsa",
          "result:#{event[:overall]}"
        ],
        actors: ["opsm-cli"]
      },

      semantic: %{
        types: ["opsm:event:trust_check", "opsm:trust:#{event[:overall]}"],
        properties: %{
          license_ok: event[:license_ok],
          sustainability_score: event[:sustainability_score]
        }
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Configuration
  # ---------------------------------------------------------------------------

  defp load_config do
    app_config = Application.get_env(:opsm, :verisimdb, [])

    %{
      base_url: System.get_env("OPSM_VERISIMDB_URL") ||
                Keyword.get(app_config, :base_url, "http://127.0.0.1:6077"),
      enabled: (System.get_env("OPSM_VERISIMDB_ENABLED") || "true") != "false" &&
               Keyword.get(app_config, :enabled, true),
      timeout: Keyword.get(app_config, :timeout, 5_000)
    }
  end

  # ---------------------------------------------------------------------------
  # Reconnection
  # ---------------------------------------------------------------------------

  defp maybe_reconnect(%{config: config} = state) do
    case VeriSimClient.new(config.base_url, timeout: config.timeout) do
      {:ok, client} ->
        case VeriSimClient.health(client) do
          {:ok, true} ->
            Logger.info("[OPSM.VeriSimDB] Reconnected to #{config.base_url}")
            %{state | client: client, connected: true}

          _ ->
            state
        end

      _ ->
        state
    end
  end
end
