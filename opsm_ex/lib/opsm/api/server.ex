# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Api.Server do
  @moduledoc """
  Local API server for OPSM UI integration.
  """

  def start_link(opts \\ []) do
    port = Keyword.get(opts, :port, 4466)
    Plug.Cowboy.http(Opsm.Api.Router, [], port: port, ip: {127, 0, 0, 1})
  end
end
