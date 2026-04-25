# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Clients.CheckyMonkey do
  @moduledoc """
  Client for Checky-Monkey code verification service.
  """

  alias Opsm.Http
  alias Opsm.Types.{
    ServiceConfig,
    HttpConfig,
    CheckyMonkeyRequest,
    CheckyMonkeyResponse,
    VerificationResult,
    OikosHealthResponse
  }

  defstruct [:client]

  @type t :: %__MODULE__{client: Req.Request.t()}

  def new(%ServiceConfig{} = config, %HttpConfig{} = http_config) do
    client = Http.build_client(http_config, base_url: config.base_url, token: config.token)
    %__MODULE__{client: client}
  end

  @doc """
  Submit a verification request.
  """
  def submit_verification(%__MODULE__{client: client}, %CheckyMonkeyRequest{} = request) do
    body = %{
      "repositoryUrl" => request.repository_url,
      "commitSha" => request.commit_sha,
      "verificationTypes" => Enum.map(request.verification_types, &encode_verification_type/1),
      "timeout" => request.timeout
    }

    case Http.post_json(client, "/verify/submit", body) do
      :ok ->
        # Return a queued response - actual status fetched via get_status
        {:ok, %CheckyMonkeyResponse{
          request_id: "pending",
          status: :queued,
          started_at: nil,
          completed_at: nil,
          results: nil
        }}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get verification status by request ID.
  """
  def get_status(%__MODULE__{client: client}, request_id) do
    case Http.get_json(client, "/verify/status/#{request_id}") do
      {:ok, json} -> {:ok, decode_response(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get verification status by request ID.
  """
  def get_verification_status(%__MODULE__{client: client}, request_id) do
    case Http.get_json(client, "/verification/#{request_id}") do
      {:ok, json} ->
        {:ok, decode_response(json)}

      {:error, reason} when is_binary(reason) ->
        if String.contains?(reason, "404") do
          {:error, :not_found}
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
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

  defp encode_verification_type(:property_tests), do: "PropertyTests"
  defp encode_verification_type(:fuzz_testing), do: "FuzzTesting"
  defp encode_verification_type(:type_checking), do: "TypeChecking"
  defp encode_verification_type(:formal_verification), do: "FormalVerification"
  defp encode_verification_type(:mutation_testing), do: "MutationTesting"

  # Decoders

  defp decode_response(json) do
    %CheckyMonkeyResponse{
      request_id: json["requestId"] || "",
      status: decode_verification_status(json["status"]),
      started_at: json["startedAt"],
      completed_at: json["completedAt"],
      results: decode_results(json["results"])
    }
  end

  defp decode_results(nil), do: nil
  defp decode_results(results) when is_list(results) do
    Enum.map(results, &decode_verification_result/1)
  end
  defp decode_results(_), do: nil

  defp decode_verification_result(json) when is_map(json) do
    %VerificationResult{
      verification_type: decode_verification_type(json["verificationType"]),
      passed: json["passed"] || false,
      coverage: json["coverage"],
      findings: [],
      duration: json["duration"] || 0
    }
  end
  defp decode_verification_result(_), do: nil

  defp decode_verification_type("PropertyTests"), do: :property_tests
  defp decode_verification_type("FuzzTesting"), do: :fuzz_testing
  defp decode_verification_type("TypeChecking"), do: :type_checking
  defp decode_verification_type("FormalVerification"), do: :formal_verification
  defp decode_verification_type("MutationTesting"), do: :mutation_testing
  defp decode_verification_type(_), do: :property_tests

  defp decode_verification_status("queued"), do: :queued
  defp decode_verification_status("running"), do: :running
  defp decode_verification_status("completed"), do: :completed
  defp decode_verification_status("failed"), do: :failed
  defp decode_verification_status(_), do: :queued

  defp decode_status("healthy"), do: :healthy
  defp decode_status("degraded"), do: :degraded
  defp decode_status(_), do: :unhealthy
end
