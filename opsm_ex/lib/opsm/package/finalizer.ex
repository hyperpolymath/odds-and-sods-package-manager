# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Package.Finalizer do
  @moduledoc """
  Commit the lockfile only for an applied package installation.

  A dry-run may resolve dependencies and produce a plan, but must not
  persist a new lockfile or rewrite an existing one.
  """

  @spec finish(map(), boolean(), (list() -> :ok | {:error, term()})) ::
          {:ok, :dry_run | :all_installed} | {:error, term()}
  def finish(_resolution, true, _persist), do: {:ok, :dry_run}

  def finish(resolution, false, persist)
      when is_map(resolution) and is_function(persist, 1) do
    case persist.(Map.values(resolution)) do
      :ok -> {:ok, :all_installed}
      {:error, reason} -> {:error, {:lockfile_persistence_failed, reason}}
    end
  end
end
