# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Api.Router do
  @moduledoc """
  Minimal REST API for OPSM UI integration.
  """

  use Plug.Router

  alias Opsm.SmartInstall
  alias Opsm.Api.Nickel

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:json, :urlencoded],
    pass: ["application/nickel", "text/nickel"],
    json_decoder: Jason

  plug :match
  plug :dispatch

  get "/health" do
    send_json(conn, 200, %{status: "ok"})
  end

  get "/backends" do
    statuses =
      SmartInstall.backends()
      |> Enum.map(fn backend ->
        {backend, SmartInstall.backend_availability(backend)}
      end)
      |> Enum.map(fn {backend, result} ->
        case result do
          {:ok, _} -> {backend, %{status: "ok"}}
          {:error, reason} -> {backend, %{status: "error", reason: reason}}
        end
      end)
      |> Map.new()

    send_json(conn, 200, %{backends: statuses})
  end

  post "/smart/plan" do
    with {:ok, payload} <- read_payload(conn),
         {:ok, tokens} <- fetch_tokens(payload) do
      plan = SmartInstall.parse(tokens)
      send_json(conn, 200, %{plan: plan, status: SmartInstall.plan_status(plan)})
    else
      {:error, reason} -> send_json(conn, 400, %{error: reason})
    end
  end

  post "/smart/apply" do
    with {:ok, payload} <- read_payload(conn),
         {:ok, tokens} <- fetch_tokens(payload) do
      plan = SmartInstall.parse(tokens)
      results = SmartInstall.execute(plan, dry_run: false)
      send_json(conn, 200, %{results: results})
    else
      {:error, reason} -> send_json(conn, 400, %{error: reason})
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp read_payload(conn) do
    case content_type(conn) do
      {:nickel, _} ->
        {:ok, body, _} = Plug.Conn.read_body(conn)
        Nickel.decode(body)

      _ ->
        {:ok, conn.body_params}
    end
  end

  defp fetch_tokens(%{"tokens" => tokens}) when is_list(tokens), do: {:ok, tokens}
  defp fetch_tokens(%{tokens: tokens}) when is_list(tokens), do: {:ok, tokens}
  defp fetch_tokens(%{"command" => command}) when is_binary(command), do: {:ok, command_to_tokens(command)}
  defp fetch_tokens(%{command: command}) when is_binary(command), do: {:ok, command_to_tokens(command)}
  defp fetch_tokens(_), do: {:error, "payload must include tokens or command"}

  defp command_to_tokens(command) do
    command
    |> String.split()
    |> Enum.drop_while(&(&1 != "install"))
    |> Enum.drop(1)
  end

  defp send_json(conn, status, data) do
    body = Jason.encode!(data)
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  defp content_type(conn) do
    case Plug.Conn.get_req_header(conn, "content-type") do
      [type | _] ->
        cond do
          String.contains?(type, "application/nickel") -> {:nickel, type}
          String.contains?(type, "text/nickel") -> {:nickel, type}
          true -> {:other, type}
        end

      _ ->
        :unknown
    end
  end
end
