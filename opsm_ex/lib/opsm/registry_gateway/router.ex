# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.RegistryGateway.Router do
  use Plug.Router

  alias Opsm.RegistryGateway

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  post "/packages/publish" do
    case RegistryGateway.handle_publish(conn.body_params) do
      {:ok, entry} ->
        send_resp(conn, 201, Jason.encode!(%{status: "published", digest: entry.digest}))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: reason}))
    end
  end

  get "/packages/:name" do
    case RegistryGateway.fetch_package(name) do
      {:ok, entry} ->
        send_resp(conn, 200, Jason.encode!(entry))

      :error ->
        send_resp(conn, 404, Jason.encode!(%{error: "not found"}))
    end
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "unsupported route"}))
  end
end
