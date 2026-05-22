# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Clients.CicdHyperA do
  @moduledoc """
  Client for CICD-Hyper-A registry and CI/CD pipeline hub.
  """

  alias Opsm.Http
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    CicdPublishRequest,
    CicdPublishResponse,
    FederationStatus,
    SyncState,
    OikosHealthResponse
  }

  defstruct [:client]

  @type t :: %__MODULE__{client: Req.Request.t()}

  def new(%ServiceConfig{} = config, %HttpConfig{} = http_config) do
    client = Http.build_client(http_config, base_url: config.base_url, token: config.token)
    %__MODULE__{client: client}
  end

  @doc """
  Publish a package to the registry.
  """
  def publish(%__MODULE__{client: client}, %CicdPublishRequest{} = request) do
    body = %{
      "manifest" => encode_manifest(request.manifest),
      "tarballUrl" => request.tarball_url,
      "attestations" => Enum.map(request.attestations, &encode_attestation/1)
    }

    case Http.post_json(client, "/packages/publish", body) do
      :ok ->
        # Fetch the publish response
        case Http.get_json(client, "/packages/#{request.manifest.name}/#{request.manifest.version}") do
          {:ok, json} -> {:ok, decode_publish_response(json)}
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get federation status for all mirrors.
  """
  def federation_status(%__MODULE__{client: client}) do
    case Http.get_json(client, "/federation/status") do
      {:ok, json} -> {:ok, decode_federation_status(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check service health.
  """
  def health(%__MODULE__{client: client}) do
    case Http.get_json(client, "/health") do
      {:ok, json} ->
        {:ok, %OikosHealthResponse{
          status: decode_status(json["status"]),
          version: json["version"] || "unknown",
          uptime: json["uptime"] || 0
        }}
      {:error, reason} -> {:error, reason}
    end
  end

  # Encoders

  defp encode_manifest(m) do
    %{
      "name" => m.name,
      "version" => m.version,
      "description" => m.description,
      "license" => m.license,
      "repository" => m.repository,
      "authors" => m.authors,
      "keywords" => m.keywords,
      "dependencies" => m.dependencies
    }
  end

  defp encode_attestation(a) do
    %{
      "attestationType" => Atom.to_string(a.attestation_type),
      "uri" => a.uri,
      "digest" => a.digest
    }
  end

  # Decoders

  defp decode_publish_response(json) do
    %CicdPublishResponse{
      package_id: json["packageId"] || "",
      version: json["version"] || "",
      published_at: json["publishedAt"] || "",
      registry_url: json["registryUrl"] || "",
      federation_status: decode_federation_status(json["federationStatus"])
    }
  end

  defp decode_federation_status(nil) do
    %FederationStatus{
      github: %SyncState{synced: false},
      gitlab: %SyncState{synced: false},
      codeberg: %SyncState{synced: false},
      radicle: %SyncState{synced: false},
      ipfs: nil
    }
  end

  defp decode_federation_status(json) do
    %FederationStatus{
      github: decode_sync_state(json["github"]),
      gitlab: decode_sync_state(json["gitlab"]),
      codeberg: decode_sync_state(json["codeberg"]),
      radicle: decode_sync_state(json["radicle"]),
      ipfs: if(json["ipfs"], do: decode_sync_state(json["ipfs"]))
    }
  end

  defp decode_sync_state(nil), do: %SyncState{synced: false}
  defp decode_sync_state(json) do
    %SyncState{
      synced: json["synced"] || false,
      last_sync: json["lastSync"],
      error: json["error"]
    }
  end

  defp decode_status("healthy"), do: :healthy
  defp decode_status("degraded"), do: :degraded
  defp decode_status(_), do: :unhealthy
end
