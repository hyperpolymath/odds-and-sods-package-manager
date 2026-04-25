# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.RegistryGateway.Store do
  @moduledoc """
  Simple in-memory store for registry data.
  """

  use Agent

  @type entry :: %{
          manifest: map(),
          imp: map(),
          digest: String.t(),
          published_at: String.t()
        }

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @spec reset() :: :ok
  def reset do
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  @spec publish(String.t(), entry()) :: entry()
  def publish(name, entry) do
    Agent.update(__MODULE__, &Map.put(&1, name, entry))
    entry
  end

  @spec fetch(String.t()) :: {:ok, entry()} | :error
  def fetch(name) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state, name) do
        nil -> :error
        entry -> {:ok, entry}
      end
    end)
  end

  @spec list_all() :: map()
  def list_all do
    Agent.get(__MODULE__, & &1)
  end
end
