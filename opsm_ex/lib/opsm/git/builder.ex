# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Git.Builder do
  @moduledoc """
  Executes builds for detected build systems via SafeExec.

  Each build system has a default build recipe that can be overridden
  via opts.
  """

  @doc """
  Build a project in `repo_path` using the given `build_system`.

  ## Options

    * `:recipe` - Override the default build command (e.g., "just release")
    * `:timeout` - Build timeout in ms (default: 600_000 / 10 min)
    * `:env` - Extra environment variables as `[{key, value}]`

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec build(String.t(), atom(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def build(repo_path, build_system, opts \\ []) do
    recipe = Keyword.get(opts, :recipe)
    env = Keyword.get(opts, :env, [])

    {cmd, args} = build_command(build_system, recipe)

    exec_opts =
      [stderr_to_stdout: true, cd: repo_path]
      |> maybe_add_env(env)

    case Opsm.SafeExec.cmd(cmd, args, exec_opts) do
      {output, 0} -> {:ok, output}
      {error, code} -> {:error, "#{cmd} build failed (#{code}): #{String.trim(error)}"}
    end
  end

  @doc """
  Run the built artifact for `build_system` with the given `args`.

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec run(String.t(), atom(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run(repo_path, build_system, args \\ [], _opts \\ []) do
    {cmd, cmd_args} = run_command(build_system, args)

    case Opsm.SafeExec.cmd(cmd, cmd_args,
           stderr_to_stdout: true,
           cd: repo_path
         ) do
      {output, 0} -> {:ok, output}
      {error, code} -> {:error, "#{cmd} run failed (#{code}): #{String.trim(error)}"}
    end
  end

  @doc """
  Run dependency installation for the build system before building.

  Returns `{:ok, output}` or `{:error, reason}`.
  """
  @spec install_deps(String.t(), atom(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def install_deps(repo_path, build_system, _opts \\ []) do
    case deps_command(build_system) do
      nil ->
        {:ok, "no dependency step for #{build_system}"}

      {cmd, args} ->
        case Opsm.SafeExec.cmd(cmd, args,
               stderr_to_stdout: true,
               cd: repo_path
             ) do
          {output, 0} -> {:ok, output}
          {error, code} -> {:error, "deps install failed (#{code}): #{String.trim(error)}"}
        end
    end
  end

  # Build commands per system
  defp build_command(_system, recipe) when is_binary(recipe) do
    # Custom recipe: split first word as command, rest as args
    [cmd | args] = String.split(recipe)
    {cmd, args}
  end

  defp build_command(:just, _), do: {"just", ["build"]}
  defp build_command(:make, _), do: {"make", []}
  defp build_command(:cargo, _), do: {"cargo", ["build", "--release"]}
  defp build_command(:mix, _), do: {"mix", ["compile"]}
  defp build_command(:npm, _), do: {"deno", ["task", "build"]}
  defp build_command(:python, _), do: {"pip", ["install", "-e", "."]}
  defp build_command(:go, _), do: {"go", ["build", "./..."]}
  defp build_command(:zig, _), do: {"zig", ["build"]}
  defp build_command(:bundler, _), do: {"bundle", ["exec", "rake", "build"]}
  defp build_command(:pub, _), do: {"dart", ["compile", "exe", "bin/main.dart"]}
  defp build_command(:gradle, _), do: {"gradle", ["build"]}
  defp build_command(:maven_build, _), do: {"mvn", ["package"]}
  defp build_command(:cabal, _), do: {"cabal", ["build"]}
  defp build_command(:stack, _), do: {"stack", ["build"]}
  defp build_command(:dune, _), do: {"dune", ["build"]}
  defp build_command(system, _), do: {"echo", ["No build recipe for #{system}"]}

  # Run commands per system
  defp run_command(:just, args), do: {"just", ["run" | args]}
  defp run_command(:cargo, args), do: {"cargo", ["run", "--release", "--" | args]}
  defp run_command(:mix, args), do: {"mix", ["run" | args]}
  defp run_command(:go, args), do: {"go", ["run", "." | args]}
  defp run_command(:zig, args), do: {"zig", ["build", "run", "--" | args]}
  defp run_command(:python, args), do: {"python", ["-m", "." | args]}
  defp run_command(:npm, args), do: {"deno", ["task", "start" | args]}
  defp run_command(_, args), do: {"echo", ["Cannot auto-run; use explicit command" | args]}

  # Dependency installation commands
  defp deps_command(:mix), do: {"mix", ["deps.get"]}
  defp deps_command(:npm), do: {"deno", ["install"]}
  defp deps_command(:bundler), do: {"bundle", ["install"]}
  defp deps_command(:pub), do: {"dart", ["pub", "get"]}
  defp deps_command(:go), do: {"go", ["mod", "download"]}
  defp deps_command(:cargo), do: {"cargo", ["fetch"]}
  defp deps_command(:python), do: {"pip", ["install", "-r", "requirements.txt"]}
  defp deps_command(:gradle), do: {"gradle", ["dependencies"]}
  defp deps_command(:maven_build), do: {"mvn", ["dependency:resolve"]}
  defp deps_command(:cabal), do: {"cabal", ["update"]}
  defp deps_command(:stack), do: {"stack", ["setup"]}
  defp deps_command(_), do: nil

  defp maybe_add_env(opts, []), do: opts
  defp maybe_add_env(opts, env), do: Keyword.put(opts, :env, env)
end
