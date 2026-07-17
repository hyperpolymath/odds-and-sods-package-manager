# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Events do
  @moduledoc """
  Event dispatcher for federation and registry propagation.

  Publishes events to the federation targets
  (GitHub, GitLab, Codeberg, Radicle, IPFS).

  Event types:
  - security-advisory: Security vulnerabilities
  - package-publish: New package published
  - package-deprecate: Package deprecated
  - package-update: Package metadata updated
  - dependency-update: Dependency graph changed
  """

  require Logger

  alias Opsm.Types.OpsmConfig

  @event_types [
    :security_advisory,
    :package_publish,
    :package_deprecate,
    :package_update,
    :dependency_update
  ]

  @type event_type ::
          :security_advisory
          | :package_publish
          | :package_deprecate
          | :package_update
          | :dependency_update

  @type event_data :: %{
          required(:package) => String.t(),
          required(:version) => String.t(),
          optional(:severity) => String.t(),
          optional(:cve_id) => String.t(),
          optional(:description) => String.t(),
          optional(:affected_versions) => [String.t()],
          optional(:patched_versions) => [String.t()],
          optional(atom()) => term()
        }

  @doc """
  Publish an event to the federation.

  ## Parameters
  - `config`: OPSM configuration
  - `event_type`: Type of event (see @event_types)
  - `event_data`: Event payload (package, version, etc.)

  ## Returns
  - `{:ok, response}` if event published successfully
  - `{:error, reason}` if publication failed

  ## Examples

      Events.publish_event(config, :security_advisory, %{
        package: "express",
        version: "4.17.0",
        severity: "high",
        cve_id: "CVE-2024-1234",
        description: "Path traversal vulnerability",
        affected_versions: ["<4.17.3"],
        patched_versions: [">=4.17.3"]
      })

      Events.publish_event(config, :package_publish, %{
        package: "my-package",
        version: "1.0.0",
        manifest: manifest_data
      })
  """
  @spec publish_event(OpsmConfig.t(), event_type(), event_data()) ::
          {:ok, map()} | {:error, term()}
  def publish_event(%OpsmConfig{} = config, event_type, event_data)
      when event_type in @event_types do
    Logger.info("Publishing event: #{event_type} for #{event_data.package}@#{event_data.version}")

    # Validate required fields
    with :ok <- validate_event_data(event_type, event_data),
         {:ok, payload} <- build_event_payload(event_type, event_data),
         {:ok, response} <- post_event(config, payload) do
      Logger.info("Event published successfully: #{response.event_id}")
      {:ok, response}
    else
      {:error, reason} ->
        Logger.error("Failed to publish event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def publish_event(_config, event_type, _event_data) do
    {:error, {:invalid_event_type, event_type}}
  end

  @doc """
  Publish a security advisory event.

  Convenience wrapper for security-advisory events.
  """
  @spec publish_security_advisory(OpsmConfig.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def publish_security_advisory(config, package, version, advisory_data) do
    event_data =
      Map.merge(
        %{
          package: package,
          version: version
        },
        advisory_data
      )

    publish_event(config, :security_advisory, event_data)
  end

  @doc """
  Notify dependents of a security advisory.

  Finds all packages that depend on the affected package and notifies them.
  """
  @spec notify_dependents(OpsmConfig.t(), String.t(), [String.t()]) ::
          {:ok, [String.t()]} | {:error, term()}
  def notify_dependents(config, package, affected_versions) do
    Logger.info("Finding dependents of #{package}")

    # In v1.0: Query local lockfiles
    # In v2.0: Query the federation dependency graph API

    # For now, return empty list (dependency graph query not implemented)
    _ = config
    _ = affected_versions

    Logger.info("Dependent notification not yet implemented")
    {:ok, []}
  end

  # Private functions

  defp validate_event_data(:security_advisory, data) do
    required = [:package, :version, :severity, :description]

    missing = Enum.filter(required, fn key -> not Map.has_key?(data, key) end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_fields, missing}}
    end
  end

  defp validate_event_data(:package_publish, data) do
    if Map.has_key?(data, :package) and Map.has_key?(data, :version) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp validate_event_data(_event_type, data) do
    # Basic validation for other event types
    if Map.has_key?(data, :package) and Map.has_key?(data, :version) do
      :ok
    else
      {:error, :missing_required_fields}
    end
  end

  defp build_event_payload(event_type, event_data) do
    payload = %{
      event_type: Atom.to_string(event_type),
      package: event_data.package,
      version: event_data.version,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      data: event_data
    }

    {:ok, payload}
  end

  defp post_event(_config, payload) do
    # Federation /events endpoint.
    # In v1.0: events are recorded locally; outbound propagation is aspirational.
    # For now, log and return a queued response.

    Logger.debug("Federation event queued: #{inspect(payload)}")

    # Simulate response
    response = %{
      event_id: generate_event_id(),
      status: "queued",
      propagation_targets: ["github", "gitlab", "codeberg", "radicle", "ipfs"]
    }

    {:ok, response}
  end

  defp generate_event_id do
    # Generate UUID for event tracking
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> then(&("evt_" <> &1))
  end

  @doc """
  Parse event from incoming webhook/notification.

  Used when receiving events from other registries or federation partners.
  """
  @spec parse_event(map()) :: {:ok, {event_type(), event_data()}} | {:error, term()}
  def parse_event(%{"event_type" => event_type_str} = payload) do
    try do
      event_type = String.to_existing_atom(event_type_str)

      if event_type in @event_types do
        event_data = Map.get(payload, "data", %{})
        {:ok, {event_type, event_data}}
      else
        {:error, {:unknown_event_type, event_type_str}}
      end
    rescue
      ArgumentError ->
        {:error, {:invalid_event_type, event_type_str}}
    end
  end

  def parse_event(_payload), do: {:error, :invalid_event_format}
end
