# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Application do
  @moduledoc """
  OTP application entrypoint. Starts the registry gateway and HTTP server.
  """

  use Application

  alias Opm.RegistryGateway

  @impl true
  def start(_type, _args) do
    children = [
      RegistryGateway.Store,
      {Plug.Cowboy, scheme: :http, plug: RegistryGateway.Router, options: [port: registry_port()]}
    ]

    opts = [strategy: :one_for_one, name: Opm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp registry_port do
    Application.get_env(:opm, :registry_port, 4050)
  end
end
