# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Registries.Registry do
  @moduledoc """
  Unified registry dispatcher.
  Routes package requests to the appropriate registry client.
  Includes caching for improved performance.
  """

  alias Opm.Registries.{Npm, Crates, Hex, Pypi, Nimble, Idris2, Git, Agentic}
  alias Opm.Cache

  @registry_modules %{
    npm: Npm,
    cargo: Crates,
    crates: Crates,
    hex: Hex,
    elixir: Hex,
    pypi: Pypi,
    python: Pypi,
    nimble: Nimble,
    nim: Nimble,
    idris2: Idris2,
    idris: Idris2,
    git: Git,
    agentic: Agentic
  }

  @doc """
  Fetch package from specified registry.
  Results are cached for improved performance.
  """
  def fetch(forth, package, version \\ "latest") do
    case get_module(forth) do
      nil ->
        {:error, "Unknown registry: #{forth}"}

      module ->
        cache_key = Cache.package_key(forth, package, version)
        Cache.fetch(cache_key, fn -> module.fetch_package(package, version) end)
    end
  end

  @doc """
  Fetch package bypassing cache.
  """
  def fetch!(forth, package, version \\ "latest") do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.fetch_package(package, version)
    end
  end

  @doc """
  Search across specified registry.
  """
  def search(forth, query, opts \\ []) do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.search(query, opts)
    end
  end

  @doc """
  Check if package exists in registry.
  """
  def exists?(forth, package) do
    case get_module(forth) do
      nil -> false
      module -> module.exists?(package)
    end
  end

  @doc """
  Get all versions from registry.
  """
  def versions(forth, package) do
    case get_module(forth) do
      nil -> {:error, "Unknown registry: #{forth}"}
      module -> module.versions(package)
    end
  end

  @doc """
  Search across ALL registries in parallel.
  Returns results from each registry.
  Handles task failures gracefully.
  """
  def search_all(query, opts \\ []) do
    forths = Keyword.get(opts, :forths, [:npm, :cargo, :hex, :pypi])
    timeout = Keyword.get(opts, :timeout, 15_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        result = search(forth, query, opts)
        {forth, result}
      end)
    end)

    results = safe_await_many(tasks, timeout)

    Enum.map(results, fn
      {forth, {:ok, packages}} -> {forth, packages}
      {forth, {:error, _}} -> {forth, []}
      {:error, forth} -> {forth, []}
    end)
    |> Map.new()
  end

  @doc """
  Check package existence across ALL registries in parallel.
  Returns map of registry -> exists?
  Handles task failures gracefully.
  """
  def exists_all?(package, opts \\ []) do
    forths = Keyword.get(opts, :forths, [:npm, :cargo, :hex, :pypi])
    timeout = Keyword.get(opts, :timeout, 10_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        {forth, exists?(forth, package)}
      end)
    end)

    results = safe_await_many(tasks, timeout)

    Enum.map(results, fn
      {forth, exists} when is_boolean(exists) -> {forth, exists}
      {:error, forth} -> {forth, false}
    end)
    |> Map.new()
  end

  @doc """
  Fetch package from ALL registries where it exists.
  Returns map of registry -> package info.
  Handles task failures gracefully.
  """
  def fetch_all(package, version \\ "latest", opts \\ []) do
    forths = Keyword.get(opts, :forths, [:npm, :cargo, :hex, :pypi])
    timeout = Keyword.get(opts, :timeout, 15_000)

    tasks = Enum.map(forths, fn forth ->
      Task.async(fn ->
        result = fetch(forth, package, version)
        {forth, result}
      end)
    end)

    results = safe_await_many(tasks, timeout)

    Enum.filter(results, fn
      {_, {:ok, _}} -> true
      _ -> false
    end)
    |> Enum.map(fn {forth, {:ok, pkg}} -> {forth, pkg} end)
    |> Map.new()
  end

  @doc """
  Get the registry module for a forth.
  """
  def get_module(forth) when is_atom(forth), do: Map.get(@registry_modules, forth)
  def get_module(forth) when is_binary(forth) do
    case safe_to_atom(forth) do
      nil -> nil
      atom -> get_module(atom)
    end
  end

  @doc """
  List all supported registries.
  """
  def supported_registries do
    @registry_modules
    |> Map.keys()
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Check if a registry is available/supported.

  ## Examples

      iex> Registry.available?(:npm)
      true

      iex> Registry.available?(:unknown)
      false
  """
  def available?(forth) when is_atom(forth) do
    Map.has_key?(@registry_modules, forth)
  end

  def available?(forth) when is_binary(forth) do
    case safe_to_atom(forth) do
      nil -> false
      atom -> available?(atom)
    end
  end

  # Helpers

  defp safe_to_atom(str) do
    String.to_existing_atom(str)
  rescue
    ArgumentError -> nil
  end

  @doc false
  # Safely await multiple tasks, catching failures and timeouts
  defp safe_await_many(tasks, timeout) do
    # Use Task.yield_many to avoid crashes on task failure
    results = Task.yield_many(tasks, timeout)

    Enum.map(results, fn
      {_task, {:ok, result}} ->
        result

      {task, {:exit, _reason}} ->
        # Task crashed - extract forth from task if possible
        Task.shutdown(task, :brutal_kill)
        {:error, :task_crashed}

      {task, nil} ->
        # Task timed out
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end)
  end
end
