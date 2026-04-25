# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.SmartInstall do
  @moduledoc """
  Smart install parsing and execution logic shared by CLI and API.
  """

  alias Opsm.Federation
  alias Opsm.Package.Native

  @backends MapSet.new([
              "rpm-ostree",
              "rpm",
              "deb",
              "dnfinition",
              "flatpak",
              "snap",
              "pacman",
              "homebrew",
              "nix",
              "guix",
              "winget",
              "choco",
              "scoop",
              "toolbox",
              "distrobox",
              "container",
              "native",
              "git",
              "source",
              "auto"
            ])

  def backends do
    MapSet.to_list(@backends)
  end

  def parse(tokens) when is_list(tokens) do
    cleaned =
      tokens
      |> Enum.map(&String.trim/1)
      |> Enum.map(&String.trim_leading(&1, "["))
      |> Enum.map(&String.trim_trailing(&1, "]"))

    Enum.reduce(cleaned, %{current: "auto", plan: %{}}, fn token, acc ->
      case String.split(token, ":", parts: 2) do
        [backend, ""] ->
          backend = normalize_backend(backend)
          %{acc | current: backend}

        [backend, rest] when rest != "" ->
          backend = normalize_backend(backend)
          pkg = String.trim(rest)
          plan = Map.update(acc.plan, backend, [pkg], fn pkgs -> pkgs ++ [pkg] end)
          %{acc | current: backend, plan: plan}

        [pkg] ->
          plan = Map.update(acc.plan, acc.current, [pkg], fn pkgs -> pkgs ++ [pkg] end)
          %{acc | plan: plan}
      end
    end)
    |> Map.get(:plan)
  end

  def normalize_backend(backend) do
    backend = String.downcase(String.trim(backend))
    if MapSet.member?(@backends, backend), do: backend, else: "auto"
  end

  def backend_availability(backend) do
    case backend do
      "toolbox" -> check_exec("toolbox")
      "distrobox" -> check_exec("distrobox")
      "container" -> check_exec("podman") |> fallback_exec("docker")
      "rpm-ostree" -> check_exec("rpm-ostree")
      "rpm" -> check_exec("dnf") |> fallback_exec("yum")
      "deb" -> check_exec("apt-get")
      "dnfinition" -> check_exec("dnfinition")
      "flatpak" -> check_exec("flatpak")
      "snap" -> check_exec("snap")
      "pacman" -> check_exec("pacman")
      "homebrew" -> check_exec("brew")
      "nix" -> check_exec("nix-env")
      "guix" -> check_exec("guix")
      "winget" -> check_exec("winget")
      "choco" -> check_exec("choco")
      "scoop" -> check_exec("scoop")
      "native" -> {:ok, "native"}
      "git" -> {:ok, "git"}
      "source" -> {:ok, "source"}
      "auto" -> {:ok, "auto"}
      _ -> {:error, "unknown backend"}
    end
  end

  def plan_status(plan) do
    Enum.map(plan, fn {backend, pkgs} ->
      status =
        case backend_availability(backend) do
          {:ok, _} -> %{status: "ok"}
          {:error, reason} -> %{status: "error", reason: reason}
        end

      {backend, Map.put(status, :packages, pkgs)}
    end)
    |> Map.new()
  end

  def execute(plan, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    scope = Keyword.get(opts, :scope, :user)
    native = Keyword.get(opts, :native, false)
    global = Keyword.get(opts, :global, false)
    dev = Keyword.get(opts, :dev, false)

    Enum.map(plan, fn {backend, pkgs} ->
      {backend, execute_backend(backend, pkgs, dry_run, scope, native, global, dev)}
    end)
  end

  defp execute_backend(backend, pkgs, dry_run, scope, native, global, dev) do
    case backend_to_port(backend) do
      {:ok, port} ->
        Enum.map(pkgs, fn pkg ->
          case Federation.install_via_port(pkg, port, dry_run: dry_run) do
            {:ok, %{command: cmd, dry_run: true}} ->
              {:dry_run, pkg, cmd}

            {:ok, output} ->
              {:ok, pkg, output}

            {:error, reason} ->
              {:error, pkg, reason}
          end
        end)

      :unsupported ->
        execute_non_port_backend(backend, pkgs, dry_run, scope, native, global, dev)
    end
  end

  defp execute_non_port_backend("git", pkgs, dry_run, _scope, _native, _global, _dev) do
    Enum.map(pkgs, fn pkg ->
      if dry_run do
        {:dry_run, pkg, "would clone and build #{pkg} via git pipeline"}
      else
        case Opsm.Git.Pipeline.from_url(pkg, []) do
          {:ok, result} -> {:ok, pkg, "installed via git pipeline (#{result.build_system})"}
          {:error, reason} -> {:error, pkg, reason}
        end
      end
    end)
  end

  defp execute_non_port_backend("source", pkgs, dry_run, _scope, _native, _global, _dev) do
    Enum.map(pkgs, fn pkg ->
      if dry_run do
        {:dry_run, pkg, "would clone and build #{pkg} from source"}
      else
        case Opsm.Git.Pipeline.from_url(pkg, []) do
          {:ok, result} -> {:ok, pkg, "built from source (#{result.build_system})"}
          {:error, reason} -> {:error, pkg, reason}
        end
      end
    end)
  end

  defp execute_non_port_backend("native", pkgs, dry_run, _scope, _native, global, dev) do
    Enum.map(pkgs, fn pkg ->
      case parse_prefixed_package(pkg) do
        {:ok, forth, name} ->
          if dry_run do
            {cmd, args} = Native.preview_command(forth, name, global: global, dev: dev)
            {:dry_run, pkg, "#{cmd} #{Enum.join(args, " ")}"}
          else
            case Native.install(forth, name, global: global, dev: dev) do
              {:ok, _} -> {:ok, pkg, "installed via native toolchain"}
              {:error, reason} -> {:error, pkg, reason}
            end
          end

        {:error, reason} ->
          {:error, pkg, reason}
      end
    end)
  end

  defp execute_non_port_backend("auto", pkgs, dry_run, scope, native, global, dev) do
    case pick_auto_port() do
      {:ok, port} ->
        execute_backend(port_to_backend(port), pkgs, dry_run, scope, native, global, dev)

      {:error, reason} ->
        Enum.map(pkgs, fn pkg -> {:error, pkg, reason} end)
    end
  end

  defp execute_non_port_backend("toolbox", pkgs, dry_run, _scope, _native, _global, _dev) do
    name = System.get_env("OPSM_TOOLBOX_NAME", "default")

    Enum.map(pkgs, fn pkg ->
      cmd = "toolbox"
      args = ["run", "--container", name, "dnf", "install", "-y", pkg]

      if dry_run do
        {:dry_run, pkg, "#{cmd} #{Enum.join(args, " ")}"}
      else
        case Opsm.SafeExec.cmd(cmd, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, pkg, output}
          {error, code} -> {:error, pkg, "#{cmd} failed (#{code}): #{error}"}
        end
      end
    end)
  end

  defp execute_non_port_backend("distrobox", pkgs, dry_run, _scope, _native, _global, _dev) do
    name = System.get_env("OPSM_DISTROBOX_NAME")

    if is_nil(name) or name == "" do
      Enum.map(pkgs, fn pkg ->
        {:error, pkg, "OPSM_DISTROBOX_NAME is required to use distrobox backend"}
      end)
    else
      Enum.map(pkgs, fn pkg ->
        cmd = "distrobox"
        args = ["enter", name, "--", "dnf", "install", "-y", pkg]

        if dry_run do
          {:dry_run, pkg, "#{cmd} #{Enum.join(args, " ")}"}
        else
          case Opsm.SafeExec.cmd(cmd, args, stderr_to_stdout: true) do
            {output, 0} -> {:ok, pkg, output}
            {error, code} -> {:error, pkg, "#{cmd} failed (#{code}): #{error}"}
          end
        end
      end)
    end
  end

  defp execute_non_port_backend("container", pkgs, dry_run, _scope, _native, _global, _dev) do
    image = System.get_env("OPSM_CONTAINER_IMAGE")
    base_cmd = System.get_env("OPSM_CONTAINER_CMD", "dnf install -y")
    runtime =
      cond do
        System.find_executable("podman") -> "podman"
        System.find_executable("docker") -> "docker"
        true -> nil
      end

    if is_nil(runtime) do
      Enum.map(pkgs, fn pkg ->
        {:error, pkg, "podman or docker is required to use container backend"}
      end)
    else
    if is_nil(image) or image == "" do
      Enum.map(pkgs, fn pkg ->
        {:error, pkg, "OPSM_CONTAINER_IMAGE is required to use container backend"}
      end)
    else
      Enum.map(pkgs, fn pkg ->
        cmd = runtime
        args = ["run", "--rm", image, "sh", "-lc", "#{base_cmd} #{pkg}"]

        if dry_run do
          {:dry_run, pkg, "#{cmd} #{Enum.join(args, " ")}"}
        else
          case Opsm.SafeExec.cmd(cmd, args, stderr_to_stdout: true) do
            {output, 0} -> {:ok, pkg, output}
            {error, code} -> {:error, pkg, "#{cmd} failed (#{code}): #{error}"}
          end
        end
      end)
    end
    end
  end

  defp execute_non_port_backend(_backend, pkgs, _dry_run, _scope, _native, _global, _dev) do
    Enum.map(pkgs, fn pkg -> {:error, pkg, "backend not executable"} end)
  end

  def backend_to_port(backend) do
    case backend do
      "rpm-ostree" -> {:ok, :rpm_ostree}
      "rpm_ostree" -> {:ok, :rpm_ostree}
      "rpm" -> {:ok, :rpm}
      "deb" -> {:ok, :deb}
      "dnfinition" -> {:ok, :dnfinition}
      "flatpak" -> {:ok, :flatpak}
      "snap" -> {:ok, :snap}
      "pacman" -> {:ok, :pacman}
      "homebrew" -> {:ok, :homebrew}
      "nix" -> {:ok, :nix}
      "guix" -> {:ok, :guix}
      "winget" -> {:ok, :winget}
      "choco" -> {:ok, :choco}
      "scoop" -> {:ok, :scoop}
      _ -> :unsupported
    end
  end

  defp port_to_backend(port) do
    case port do
      :rpm_ostree -> "rpm-ostree"
      :rpm -> "rpm"
      :deb -> "deb"
      :dnfinition -> "dnfinition"
      :flatpak -> "flatpak"
      :snap -> "snap"
      :pacman -> "pacman"
      :homebrew -> "homebrew"
      :nix -> "nix"
      :guix -> "guix"
      :winget -> "winget"
      :choco -> "choco"
      :scoop -> "scoop"
    end
  end

  defp pick_auto_port do
    candidates = [:rpm_ostree, :rpm, :deb, :pacman, :homebrew, :nix, :guix, :winget, :choco, :scoop]

    Enum.reduce_while(candidates, {:error, "no suitable backend available"}, fn port, _acc ->
      case Federation.check_connection_port(port) do
        {:ok, _} -> {:halt, {:ok, port}}
        {:error, _} -> {:cont, {:error, "no suitable backend available"}}
      end
    end)
  end

  defp parse_prefixed_package(pkg) do
    cond do
      String.starts_with?(pkg, "@") and String.contains?(pkg, "/") ->
        "@" <> rest = pkg
        [forth, name] = String.split(rest, "/", parts: 2)
        {:ok, Opsm.Validation.safe_to_forth(forth), name}

      String.starts_with?(pkg, "@") and String.contains?(pkg, ":") ->
        "@" <> rest = pkg
        [forth, name] = String.split(rest, ":", parts: 2)
        {:ok, Opsm.Validation.safe_to_forth(forth), name}

      true ->
        {:error, "native backend requires @forth:pkg or @forth/pkg prefix"}
    end
  end

  defp fallback_exec({:ok, path}, _fallback), do: {:ok, path}
  defp fallback_exec({:error, _}, fallback), do: check_exec(fallback)

  defp check_exec(cmd) do
    case System.find_executable(cmd) do
      nil -> {:error, "#{cmd} not found"}
      path -> {:ok, path}
    end
  end
end
