# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Api.MobileRouter do
  @moduledoc """
  REST API endpoints for OPSM mobile application.
  """

  use Plug.Router

  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:json],
    json_decoder: Jason

  plug :match
  plug :dispatch

  get "/api/health" do
    send_json(conn, 200, %{
      status: "healthy",
      version: "1.0.1",
      service: "opsm-api"
    })
  end

  get "/api/packages/search" do
    query = conn.query_params["q"] || ""
    registry = conn.query_params["registry"]

    # Mock search results for testing
    packages = [
      %{
        name: "react",
        version: "18.2.0",
        registry: "npm",
        description: "A JavaScript library for building user interfaces"
      },
      %{
        name: "vue",
        version: "3.3.4",
        registry: "npm",
        description: "Progressive JavaScript Framework"
      },
      %{
        name: "axum",
        version: "0.7.3",
        registry: "crates",
        description: "Web framework for Rust"
      }
    ]
    |> Enum.filter(fn pkg ->
      String.contains?(String.downcase(pkg.name), String.downcase(query))
    end)
    |> Enum.filter(fn pkg ->
      is_nil(registry) || pkg.registry == registry
    end)

    send_json(conn, 200, %{
      packages: packages,
      total: length(packages)
    })
  end

  get "/api/packages/:name/:version" do
    send_json(conn, 200, %{
      name: name,
      version: version,
      registry: "npm",
      description: "Package information for #{name}@#{version}",
      dependencies: %{},
      metadata: %{
        license: "MIT",
        homepage: "https://example.com"
      }
    })
  end

  post "/api/packages/install" do
    payload = conn.body_params

    send_json(conn, 200, %{
      success: true,
      message: "Installed #{payload["name"]}@#{payload["version"]} from #{payload["registry"]}"
    })
  end

  get "/api/packages/installed" do
    # Mock installed packages
    packages = [
      %{
        name: "lodash",
        version: "4.17.21",
        registry: "npm",
        description: "Lodash modular utilities"
      },
      %{
        name: "axios",
        version: "1.6.0",
        registry: "npm",
        description: "Promise based HTTP client"
      }
    ]

    send_json(conn, 200, packages)
  end

  post "/api/audit/lockfile" do
    _payload = conn.body_params

    send_json(conn, 200, %{
      issues: [
        %{
          severity: "medium",
          package: "lodash",
          description: "Prototype pollution vulnerability"
        }
      ],
      sustainability_score: 85.5,
      security_score: 72.3
    })
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, data) do
    body = Jason.encode!(data)
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end
end
