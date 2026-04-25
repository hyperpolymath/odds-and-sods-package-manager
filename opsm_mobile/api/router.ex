# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Api.Router do
  @moduledoc """
  HTTP API router for mobile wrapper (Tauri 2.0).

  Provides 5 core endpoints for package management operations:
  - POST /api/packages/install - Install packages
  - GET /api/packages/search - Search for packages
  - GET /api/packages/:name/:version - Get package info
  - POST /api/lockfile/audit - Audit lockfile for vulnerabilities
  - GET /api/packages/installed - List installed packages
  """

  use Plug.Router

  alias Opsm.Api.PackageController

  plug :match
  plug Plug.Parsers, parsers: [:json], json_decoder: Jason
  plug :dispatch

  # Install packages
  post "/api/packages/install" do
    case PackageController.install(conn.body_params) do
      {:ok, result} ->
        send_resp(conn, 200, Jason.encode!(%{status: "success", result: result}))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # Search for packages
  get "/api/packages/search" do
    query = conn.query_params["q"] || ""
    registry = conn.query_params["registry"]

    case PackageController.search(query, registry) do
      {:ok, results} ->
        send_resp(conn, 200, Jason.encode!(%{results: results}))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # Get package info
  get "/api/packages/:name/:version" do
    registry = conn.query_params["registry"]

    case PackageController.get_package_info(name, version, registry) do
      {:ok, info} ->
        send_resp(conn, 200, Jason.encode!(info))

      {:error, :not_found} ->
        send_resp(conn, 404, Jason.encode!(%{error: "Package not found"}))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # Audit lockfile
  post "/api/lockfile/audit" do
    case PackageController.audit_lockfile(conn.body_params) do
      {:ok, audit_result} ->
        send_resp(conn, 200, Jason.encode!(audit_result))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # List installed packages
  get "/api/packages/installed" do
    case PackageController.list_installed() do
      {:ok, packages} ->
        send_resp(conn, 200, Jason.encode!(%{packages: packages}))

      {:error, reason} ->
        send_resp(conn, 400, Jason.encode!(%{error: to_string(reason)}))
    end
  end

  # Health check
  get "/api/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "healthy", version: "1.0.0"}))
  end

  match _ do
    send_resp(conn, 404, Jason.encode!(%{error: "Route not found"}))
  end
end
