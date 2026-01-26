# SPDX-License-Identifier: PMPL-1.0
defmodule Opsm.Package.Native do
  @moduledoc """
  Native toolchain delegation.

  When enabled, delegates package operations to native package managers
  (npm, cargo, mix, pip, etc.) instead of downloading and unpacking manually.

  Benefits:
  - Proper dependency resolution
  - Native build steps executed
  - Integration with toolchain lockfiles
  - Platform-specific optimizations
  """

  alias Opsm.Federation
  alias Opsm.Validation

  @doc """
  Install a package using its native toolchain.
  Returns {:ok, result} or {:error, reason}.
  """
  def install(forth, package_name, opts \\ []) do
    version = Keyword.get(opts, :version)
    global = Keyword.get(opts, :global, false)
    dev = Keyword.get(opts, :dev, false)

    # Validate inputs to prevent command injection
    with {:ok, _} <- Validation.validate_package_name(package_name, forth),
         {:ok, _} <- Validation.validate_version(version) do
      case Federation.check_toolchain(forth) do
        {:error, info} ->
          {:error, "Missing toolchain: #{info.message}"}

        {:ok, info} ->
          IO.puts("  Using native toolchain: #{Map.get(info, :command, "detected")}")
          do_native_install(forth, package_name, version, global, dev)
      end
    else
      {:error, reason} ->
        {:error, "Validation failed: #{reason}"}
    end
  end

  @doc """
  Remove a package using its native toolchain.
  """
  def remove(forth, package_name, opts \\ []) do
    global = Keyword.get(opts, :global, false)

    case Federation.check_toolchain(forth) do
      {:error, info} ->
        {:error, "Missing toolchain: #{info.message}"}

      {:ok, _info} ->
        do_native_remove(forth, package_name, global)
    end
  end

  @doc """
  Check if native mode is available for a forth.
  """
  def available?(forth) do
    case Federation.check_toolchain(forth) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get the native command that would be run.
  Useful for dry-run mode.
  """
  def preview_command(forth, package_name, opts \\ []) do
    version = Keyword.get(opts, :version)
    global = Keyword.get(opts, :global, false)
    dev = Keyword.get(opts, :dev, false)

    build_install_command(forth, package_name, version, global, dev)
  end

  # Install implementations

  defp do_native_install(:npm, package, version, global, dev) do
    {cmd, args} = build_install_command(:npm, package, version, global, dev)
    run_command(cmd, args)
  end

  defp do_native_install(:cargo, package, version, _global, _dev) do
    {cmd, args} = build_install_command(:cargo, package, version, false, false)
    run_command(cmd, args)
  end

  defp do_native_install(:hex, package, version, _global, dev) do
    {cmd, args} = build_install_command(:hex, package, version, false, dev)
    run_command(cmd, args)
  end

  defp do_native_install(:pypi, package, version, global, _dev) do
    {cmd, args} = build_install_command(:pypi, package, version, global, false)
    run_command(cmd, args)
  end

  defp do_native_install(:gem, package, version, global, _dev) do
    {cmd, args} = build_install_command(:gem, package, version, global, false)
    run_command(cmd, args)
  end

  defp do_native_install(:go, package, version, _global, _dev) do
    {cmd, args} = build_install_command(:go, package, version, false, false)
    run_command(cmd, args)
  end

  defp do_native_install(:pub, package, version, _global, dev) do
    {cmd, args} = build_install_command(:pub, package, version, false, dev)
    run_command(cmd, args)
  end

  defp do_native_install(forth, _package, _version, _global, _dev) do
    {:error, "Native install not supported for @#{forth}"}
  end

  # Remove implementations

  defp do_native_remove(:npm, package, global) do
    args = if global, do: ["uninstall", "-g", package], else: ["uninstall", package]
    run_command("npm", args)
  end

  defp do_native_remove(:cargo, package, _global) do
    run_command("cargo", ["uninstall", package])
  end

  defp do_native_remove(:hex, package, _global) do
    # mix deps.unlock + remove from mix.exs (interactive)
    IO.puts("  Note: Remove '#{package}' from mix.exs deps, then run 'mix deps.unlock #{package}'")
    {:ok, :manual_required}
  end

  defp do_native_remove(:pypi, package, global) do
    args = if global, do: ["uninstall", "-y", package], else: ["uninstall", "-y", package]
    run_command("pip", args)
  end

  defp do_native_remove(:gem, package, _global) do
    run_command("gem", ["uninstall", package])
  end

  defp do_native_remove(forth, _package, _global) do
    {:error, "Native remove not supported for @#{forth}"}
  end

  # Command builders

  defp build_install_command(:npm, package, version, global, dev) do
    pkg_spec = if version, do: "#{package}@#{version}", else: package

    args = cond do
      global && dev -> ["install", "-g", "--save-dev", pkg_spec]
      global -> ["install", "-g", pkg_spec]
      dev -> ["install", "--save-dev", pkg_spec]
      true -> ["install", pkg_spec]
    end

    {"npm", args}
  end

  defp build_install_command(:cargo, package, version, _global, _dev) do
    args = if version do
      ["install", package, "--version", version]
    else
      ["install", package]
    end

    {"cargo", args}
  end

  defp build_install_command(:hex, package, version, _global, _dev) do
    # For hex, we'd add to mix.exs - show the dep line
    version_spec = if version, do: "\"~> #{version}\"", else: "\">= 0.0.0\""
    IO.puts("  Add to mix.exs deps: {:#{package}, #{version_spec}}")
    IO.puts("  Then run: mix deps.get")
    {"mix", ["deps.get"]}
  end

  defp build_install_command(:pypi, package, version, global, _dev) do
    pkg_spec = if version, do: "#{package}==#{version}", else: package

    args = if global do
      ["install", pkg_spec]
    else
      ["install", "--user", pkg_spec]
    end

    {"pip", args}
  end

  defp build_install_command(:gem, package, version, global, _dev) do
    args = cond do
      version && global -> ["install", package, "-v", version]
      version -> ["install", package, "-v", version, "--user-install"]
      global -> ["install", package]
      true -> ["install", package, "--user-install"]
    end

    {"gem", args}
  end

  defp build_install_command(:go, package, version, _global, _dev) do
    pkg_spec = if version, do: "#{package}@#{version}", else: "#{package}@latest"
    {"go", ["install", pkg_spec]}
  end

  defp build_install_command(:pub, package, version, _global, dev) do
    args = if dev do
      ["pub", "add", "--dev", package]
    else
      ["pub", "add", package]
    end

    args = if version, do: args ++ ["--version", version], else: args
    {"dart", args}
  end

  defp build_install_command(forth, package, _version, _global, _dev) do
    {to_string(forth), ["install", package]}
  end

  # Command execution with timeout (D5)

  # Default timeout: 10 minutes for package installs
  @default_timeout_ms 10 * 60 * 1000

  defp run_command(cmd, args, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout_ms)

    IO.puts("  $ #{cmd} #{Enum.join(args, " ")}")

    # Use Port for better control and timeout handling
    task = Task.async(fn ->
      run_command_sync(cmd, args)
    end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        # Timeout - kill the task
        Task.shutdown(task, :brutal_kill)
        {:error, "Command timed out after #{div(timeout, 1000)} seconds"}
    end
  end

  defp run_command_sync(cmd, args) do
    # Find the executable
    case System.find_executable(cmd) do
      nil ->
        {:error, "Command not found: #{cmd}"}

      exe_path ->
        port = Port.open({:spawn_executable, exe_path}, [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          args: args
        ])

        collect_output(port, [])
    end
  end

  defp collect_output(port, acc) do
    receive do
      {^port, {:data, data}} ->
        # Print output in real-time
        IO.write(data)
        collect_output(port, [data | acc])

      {^port, {:exit_status, 0}} ->
        {:ok, :installed}

      {^port, {:exit_status, code}} ->
        output = acc |> Enum.reverse() |> Enum.join()
        {:error, "Command failed with exit code #{code}: #{String.slice(output, 0, 500)}"}
    after
      # This shouldn't be reached due to Task timeout, but just in case
      @default_timeout_ms + 1000 ->
        Port.close(port)
        {:error, "Command timed out"}
    end
  end
end
