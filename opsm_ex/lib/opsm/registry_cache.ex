# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.RegistryCache do
  @moduledoc """
  ETS-based cache for registry lookups during dependency resolution.

  Avoids repeated HTTP calls for the same package/version across resolution
  iterations. Cache entries expire after a configurable TTL (default 5 minutes).
  """

  @table :opsm_registry_cache
  @default_ttl_ms 5 * 60 * 1000

  @doc """
  Initialize the cache table. Safe to call multiple times.
  """
  def init do
    if :ets.info(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc """
  Get a cached value, or compute and cache it.

  ## Examples

      RegistryCache.fetch_or_compute({:versions, :npm, "express"}, fn ->
        Registry.versions(:npm, "express")
      end)
  """
  def fetch_or_compute(key, compute_fn, ttl_ms \\ @default_ttl_ms) do
    init()
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] when expires_at > now ->
        value

      _ ->
        value = compute_fn.()
        :ets.insert(@table, {key, value, now + ttl_ms})
        value
    end
  end

  @doc """
  Clear all cached entries.
  """
  def clear do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Get cache statistics (hit count approximated by table size).
  """
  def stats do
    if :ets.info(@table) != :undefined do
      %{size: :ets.info(@table, :size), memory_words: :ets.info(@table, :memory)}
    else
      %{size: 0, memory_words: 0}
    end
  end
end
