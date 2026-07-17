# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.SafeExec do
  @moduledoc """
  Safe wrapper around System.cmd with allowlist and argument validation.
  """

  alias Opsm.Validation

  @default_allowlist MapSet.new([
                       "git",
                       "tar",
                       "unzip",
                       "nickel",
                       "nickel-config-reporter",
                       "spdx-tool",
                       "license-checker",
                       "dnf",
                       "yum",
                       "rpm-ostree",
                       "apt-get",
                       "apt-cache",
                       "pacman",
                       "brew",
                       "nix-env",
                       "guix",
                       "flatpak",
                       "snap",
                       "winget",
                       "choco",
                       "scoop",
                       "toolbox",
                       "distrobox",
                       "podman",
                       "docker",
                       # Build tools (Phase 1: git build pipeline)
                       "just",
                       "make",
                       "cargo",
                       "mix",
                       "deno",
                       "go",
                       "zig",
                       "pip",
                       "bundle",
                       "dart",
                       "gradle",
                       "mvn",
                       "cabal",
                       "stack",
                       "dune",
                       "python",
                       "python3",
                       # System PM query tools (Phase 2)
                       "dpkg-query",
                       "rpm",
                       "fpm",
                       "nix-env"
                     ])

  @doc """
  Run a command with validation. Returns {output, exit_status} like System.cmd.
  """
  def cmd(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    allowlist =
      opts
      |> Keyword.get(:allowlist, @default_allowlist)
      |> normalize_allowlist()

    with :ok <- validate_command(command, allowlist),
         :ok <- validate_args(args) do
      # :allowlist is ours, not System.cmd's — it rejects unknown options
      System.cmd(command, args, Keyword.delete(opts, :allowlist))
    else
      {:error, reason} -> {"safe-exec blocked: #{reason}", 1}
    end
  end

  defp validate_command(command, allowlist) do
    name = Path.basename(command)

    cond do
      String.trim(command) == "" ->
        {:error, "command is empty"}

      not MapSet.member?(allowlist, name) ->
        {:error, "command not allowed: #{name}"}

      is_nil(System.find_executable(command)) ->
        {:error, "command not found: #{command}"}

      true ->
        :ok
    end
  end

  defp validate_args(args) do
    args
    |> Enum.reduce_while(:ok, fn arg, _acc ->
      case validate_arg(arg) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_arg(arg) when is_binary(arg) do
    cond do
      String.contains?(arg, "\0") ->
        {:error, "argument contains null byte"}

      match?({:error, _}, Validation.sanitize_for_shell(arg)) ->
        {:error, "argument contains unsafe characters"}

      true ->
        :ok
    end
  end

  defp validate_arg(_), do: {:error, "argument must be a string"}

  defp normalize_allowlist(%MapSet{} = allowlist), do: allowlist
  defp normalize_allowlist(list) when is_list(list), do: MapSet.new(list)
end
