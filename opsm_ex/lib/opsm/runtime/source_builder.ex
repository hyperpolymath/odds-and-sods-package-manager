# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Runtime.SourceBuilder do
  @moduledoc """
  Source-build orchestrator for runtime plugins with strategy 'BuildFromSource
  or 'DelegateToManager.

  For tools that must be compiled from source (Erlang, OCaml, Ruby) or that
  delegate to a manager (Rust via rustup, Haskell via ghcup, OCaml via opam,
  Elixir via kerl), this module:

  1. Checks that system_dependencies are satisfied.
  2. Downloads and extracts the source archive (for BuildFromSource).
  3. Executes `build_steps` in order, substituting `{{install_dir}}` etc.
  4. For DelegateToManager: runs `delegate_install_command` and verifies
     the `health_check` afterwards.

  ## Environment

  - `OPSM_BUILD_CONCURRENCY` — override `$(nproc)` parallel jobs (default: CPU count)
  - `OPSM_BUILD_CACHE` — directory for source download cache (default: `~/.opsm/build-cache`)

  ## Build directory layout

      ~/.opsm/runtimes/<tool>/<version>/      ← install prefix ({{install_dir}})
      ~/.opsm/build-cache/<tool>-<version>/   ← extracted source (temp)
  """

  alias Opsm.Verified.Http, as: VerifiedHttp

  @opsm_dir Path.expand("~/.opsm")
  @build_cache Path.join(@opsm_dir, "build-cache")
  @runtimes_dir Path.join(@opsm_dir, "runtimes")

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Install a tool using the build strategy declared in its plugin definition.

  Accepts the parsed plugin map (from Nickel) and the resolved version string.

  Returns `:ok` or `{:error, reason}`.
  """
  def install(plugin, version) do
    strategy = get_strategy(plugin)
    tool_name = plugin["name"] || plugin[:name]
    install_dir = install_prefix(tool_name, version)

    with :ok <- check_system_dependencies(plugin) do
      case strategy do
        :delegate_to_manager ->
          delegate_install(plugin, version, install_dir)

        :build_from_source ->
          source_install(plugin, version, install_dir)

        :both ->
          # Prebuilt binaries are not yet supported (the availability probe
          # was a stub always returning false) — build from source for now.
          source_install(plugin, version, install_dir)

        :prebuilt_binary ->
          # Source builder is not the right path for prebuilt — caller error
          {:error, {:wrong_strategy, :prebuilt_binary}}

        unknown ->
          {:error, {:unknown_strategy, unknown}}
      end
    end
  end

  @doc """
  Check whether all system_dependencies are satisfied for a plugin.
  Returns `:ok` or `{:error, {:missing_deps, [dep_name]}}`.
  """
  def check_system_dependencies(plugin) do
    deps = plugin["system_dependencies"] || plugin[:system_dependencies] || []

    missing =
      Enum.filter(deps, fn dep ->
        check_cmd = dep["check_command"] || dep[:check_command]
        not command_succeeds?(check_cmd)
      end)
      |> Enum.map(fn dep -> dep["name"] || dep[:name] end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_system_dependencies, missing}}
    end
  end

  # ---------------------------------------------------------------------------
  # Delegate-to-manager install (rustup, ghcup, opam, etc.)
  # ---------------------------------------------------------------------------

  defp delegate_install(plugin, version, _install_dir) do
    delegate = plugin["install"]["delegate_to"] || plugin[:install][:delegate_to]
    cmd_template = plugin["install"]["delegate_install_command"] ||
                   plugin[:install][:delegate_install_command]

    cmd = String.replace(cmd_template, "{{version}}", version)

    with :ok <- ensure_delegate_available(delegate),
         :ok <- run_command(cmd) do
      verify_health_check(plugin)
    end
  end

  defp ensure_delegate_available(delegate) do
    case System.find_executable(delegate) do
      nil -> {:error, {:delegate_not_found, delegate}}
      _ -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Build-from-source install
  # ---------------------------------------------------------------------------

  defp source_install(plugin, version, install_dir) do
    tool_name = plugin["name"] || plugin[:name]
    build_steps = plugin["install"]["build_steps"] || plugin[:install][:build_steps] || []

    with :ok <- File.mkdir_p(install_dir),
         :ok <- File.mkdir_p(@build_cache),
         {:ok, source_dir} <- download_and_extract_source(tool_name, version, plugin),
         :ok <- run_build_steps(build_steps, install_dir, source_dir) do
      verify_health_check(plugin)
    end
  end

  defp download_and_extract_source(tool_name, version, plugin) do
    # Try to get source URL from url_handler if present
    url_handler = plugin["url_handler"] || plugin[:url_handler]
    source_url = resolve_source_url(tool_name, version, url_handler)

    build_dir = Path.join(@build_cache, "#{tool_name}-#{version}")

    case source_url do
      nil ->
        {:error, :no_source_url}

      url ->
        archive_path = Path.join(@build_cache, "#{tool_name}-#{version}.tar.gz")

        with :ok <- download_file(url, archive_path),
             :ok <- extract_archive(archive_path, build_dir) do
          {:ok, build_dir}
        end
    end
  end

  defp resolve_source_url(tool_name, version, nil) do
    # Fall back to GitHub archive URL for tools without a custom handler
    "https://github.com/#{github_owner(tool_name)}/#{github_repo(tool_name)}/archive/refs/tags/#{version}.tar.gz"
  end

  defp resolve_source_url(_tool_name, version, url_handler) do
    template = url_handler["archive_url_template"] || url_handler[:archive_url_template]
    if template do
      String.replace(template, "{{version}}", version)
    else
      nil
    end
  end

  defp run_build_steps(steps, install_dir, working_dir) do
    nproc = System.get_env("OPSM_BUILD_CONCURRENCY") || "#{System.schedulers_online()}"

    Enum.reduce_while(steps, :ok, fn step, :ok ->
      expanded =
        step
        |> String.replace("{{install_dir}}", install_dir)
        |> String.replace("$(nproc)", nproc)

      case run_command_in(expanded, working_dir) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:build_step_failed, step, reason}}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Health check verification
  # ---------------------------------------------------------------------------

  defp verify_health_check(plugin) do
    check = plugin["health_check"] || plugin[:health_check]
    if check && command_succeeds?(check) do
      :ok
    else
      {:error, {:health_check_failed, check}}
    end
  end

  # ---------------------------------------------------------------------------
  # Utility helpers
  # ---------------------------------------------------------------------------

  defp install_prefix(tool_name, version) do
    Path.join([@runtimes_dir, tool_name, version])
  end

  defp download_file(url, dest_path) do
    case VerifiedHttp.get(url, receive_timeout: 120_000) do
      {:ok, %{body: body, status: status}} when status in 200..299 ->
        File.write(dest_path, body)

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_archive(archive_path, dest_dir) do
    File.mkdir_p!(dest_dir)
    result = System.cmd("tar", ["-xzf", archive_path, "-C", dest_dir, "--strip-components=1"],
                        stderr_to_stdout: true)
    case result do
      {_, 0} -> :ok
      {output, code} -> {:error, {:tar_failed, code, output}}
    end
  end

  defp run_command(cmd) do
    run_command_in(cmd, File.cwd!())
  end

  defp run_command_in(cmd, cwd) do
    case System.cmd("sh", ["-c", cmd], cd: cwd, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, {:command_failed, code, output}}
    end
  end

  defp command_succeeds?(nil), do: true
  defp command_succeeds?(cmd) do
    case System.cmd("sh", ["-c", "#{cmd} >/dev/null 2>&1"], []) do
      {_, 0} -> true
      _ -> false
    end
  end

  # Minimal GitHub org/repo guesses for source archive fallback
  defp github_owner("erlang"), do: "erlang"
  defp github_owner("elixir"), do: "elixir-lang"
  defp github_owner("ruby"), do: "ruby"
  defp github_owner("ocaml"), do: "ocaml"
  defp github_owner(tool), do: tool

  defp github_repo("erlang"), do: "otp"
  defp github_repo("elixir"), do: "elixir"
  defp github_repo("ruby"), do: "ruby"
  defp github_repo("ocaml"), do: "ocaml"
  defp github_repo(tool), do: tool

  defp get_strategy(plugin) do
    strategy_str = get_in(plugin, ["install", "strategy"]) ||
                   get_in(plugin, [:install, :strategy])

    case strategy_str do
      "PrebuiltBinary"    -> :prebuilt_binary
      "BuildFromSource"   -> :build_from_source
      "Both"              -> :both
      "DelegateToManager" -> :delegate_to_manager
      atom when is_atom(atom) -> atom
      _ -> :unknown
    end
  end
end
