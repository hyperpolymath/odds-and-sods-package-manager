# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Cache do
  @moduledoc """
  ETS-based cache for registry responses.

  Reduces network requests by caching:
  - Package metadata
  - Search results
  - Existence checks

  Cache entries expire based on configurable TTL.
  Designed for CLI use (no supervision required).
  """

  @table_name :opsm_cache
  @default_ttl_ms 5 * 60 * 1000  # 5 minutes

  # Client API

  @doc """
  Ensure the cache table exists.
  Called automatically by other functions.
  """
  def ensure_started do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
        :ok
      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Get a cached value by key.
  Returns {:ok, value} or :miss.
  """
  def get(key) do
    ensure_started()

    case :ets.lookup(@table_name, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          # Expired, clean it up
          :ets.delete(@table_name, key)
          :miss
        end

      [] ->
        :miss
    end
  rescue
    ArgumentError ->
      :miss
  end

  @doc """
  Put a value in the cache with optional TTL.
  """
  def put(key, value, ttl_ms \\ @default_ttl_ms) do
    ensure_started()
    expires_at = System.monotonic_time(:millisecond) + ttl_ms
    :ets.insert(@table_name, {key, value, expires_at})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Delete a specific key from cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Clear all cache entries.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc """
  Get cache statistics.
  """
  def stats do
    info = :ets.info(@table_name)
    %{
      size: Keyword.get(info, :size, 0),
      memory_bytes: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
    }
  rescue
    ArgumentError ->
      %{size: 0, memory_bytes: 0}
  end

  @doc """
  Get or compute a cached value.
  If cache miss, computes the value using the provided function and caches it.
  """
  def fetch(key, compute_fn, ttl_ms \\ @default_ttl_ms) do
    case get(key) do
      {:ok, value} ->
        value

      :miss ->
        value = compute_fn.()
        # Only cache successful results
        case value do
          {:ok, _} -> put(key, value, ttl_ms)
          _ -> :ok
        end
        value
    end
  end

  # Cache key builders

  @doc """
  Build a cache key for package fetch.
  """
  def package_key(forth, name, version) do
    {:package, forth, name, version}
  end

  @doc """
  Build a cache key for search.
  """
  def search_key(forth, query) do
    {:search, forth, query}
  end

  @doc """
  Build a cache key for existence check.
  """
  def exists_key(forth, name) do
    {:exists, forth, name}
  end

end
