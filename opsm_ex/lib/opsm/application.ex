# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Application do
  @moduledoc """
  OTP application entrypoint. Starts the registry gateway HTTP server.
  """

  use Application

  alias Opsm.RegistryGateway

  @impl true
  def start(_type, _args) do
    children = [
      RegistryGateway.Store,
      {Bandit, plug: RegistryGateway.Router, scheme: :http, port: registry_port(), ip: {127, 0, 0, 1}}
    ]

    opts = [strategy: :one_for_one, name: Opsm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp registry_port do
    Application.get_env(:opsm, :registry_port, 4050)
  end
end
