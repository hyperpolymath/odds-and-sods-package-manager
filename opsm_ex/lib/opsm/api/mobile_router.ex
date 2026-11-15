# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Api.MobileRouter do
  @moduledoc """
  Loopback mobile API for the implemented subset of OPSM.

  Incomplete endpoints must return 501 instead of claiming that a package
  was installed, found in a registry, or successfully audited.
  """

  use Plug.Router

  plug(Plug.Logger)

  plug(Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason
  )

  plug(:match)
  plug(:dispatch)

  get "/api/health" do
    version =
      case Application.spec(:opsm, :vsn) do
        nil -> "unknown"
        vsn -> to_string(vsn)
      end

    send_json(conn, 200, %{
      status: "healthy",
      version: version,
      service: "opsm-mobile-api",
      capability_discovery: "/api/capabilities"
    })
  end

  get "/api/capabilities" do
    send_json(conn, 200, %{
      protocol_version: "1",
      operations: %{
        search: "unavailable",
        package_info: "unavailable",
        install: "unavailable",
        installed: "unavailable",
        audit_lockfile: "unavailable"
      }
    })
  end

  get "/api/packages/search" do
    unavailable(conn, "search")
  end

  get "/api/packages/:name/:version" do
    send_json(conn, 501, %{
      error: "not_implemented",
      operation: "package_info",
      status: "unavailable",
      requested: %{name: name, version: version}
    })
  end

  # Installing packages requires a real core bridge and caller authorization.
  # Until those are implemented, the route must not indicate success.
  post "/api/packages/install" do
    unavailable(conn, "install")
  end

  get "/api/packages/installed" do
    # The local installed-state reader suppresses persistence read errors.
    # Keep this unavailable until a typed, authorized core reader can
    # distinguish an empty state from a corrupted or inaccessible one.
    unavailable(conn, "installed")
  end

  post "/api/audit/lockfile" do
    unavailable(conn, "audit_lockfile")
  end

  match _ do
    send_json(conn, 404, %{error: "not_found"})
  end

  defp unavailable(conn, operation) do
    send_json(conn, 501, %{
      error: "not_implemented",
      operation: operation,
      status: "unavailable"
    })
  end

  defp send_json(conn, status, data) do
    body = Jason.encode!(data)

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    |> Plug.Conn.send_resp(status, body)
  end
end
