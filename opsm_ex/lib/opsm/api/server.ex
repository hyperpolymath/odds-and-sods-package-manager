# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Api.Server do
  @moduledoc """
  Local API server for OPSM UI integration.
  """

  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, 4466)
    Bandit.start_link(plug: Opsm.Api.Router, scheme: :http, port: port, ip: {127, 0, 0, 1})
  end
end
