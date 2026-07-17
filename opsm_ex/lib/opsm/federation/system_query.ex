# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Federation.SystemQuery do
  @moduledoc """
  Query system package managers for installed packages and versions.

  All commands are read-only (no mutations) and executed via SafeExec.
  """

  @doc """
  Query all installed packages from a system package manager.

  Returns `{:ok, [%{name: name, version: version}]}` or `{:error, reason}`.
  """
  @spec query_installed(atom()) :: {:ok, [map()]} | {:error, String.t()}
  def query_installed(port_name) do
    case query_command(port_name) do
      nil ->
        {:error, "No query command for #{port_name}"}

      {cmd, args, parser} ->
        case Opsm.SafeExec.cmd(cmd, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, parser.(output)}
          {error, code} -> {:error, "#{cmd} query failed (#{code}): #{String.trim(error)}"}
        end
    end
  end

  @doc """
  Check if a specific package is available in the system PM repos.

  Returns `{:ok, %{available: true, versions: [...]}}` or `{:error, reason}`.
  """
  @spec query_available(atom(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def query_available(port_name, package_name) do
    case search_command(port_name, package_name) do
      nil ->
        {:error, "No search command for #{port_name}"}

      {cmd, args, parser} ->
        case Opsm.SafeExec.cmd(cmd, args, stderr_to_stdout: true) do
          {output, 0} -> {:ok, parser.(output, package_name)}
          {_error, _code} -> {:ok, %{available: false, versions: []}}
        end
    end
  end

  @doc """
  Get the installed version of a specific package.

  Returns `{:ok, version}` or `{:error, :not_installed}`.
  """
  @spec query_version(atom(), String.t()) :: {:ok, String.t()} | {:error, atom() | String.t()}
  def query_version(port_name, package_name) do
    case query_installed(port_name) do
      {:ok, packages} ->
        case Enum.find(packages, fn pkg -> pkg.name == package_name end) do
          nil -> {:error, :not_installed}
          pkg -> {:ok, pkg.version}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Detect which system package manager is available on this system.

  Returns `{:ok, port_name}` or `{:error, :none_found}`.
  """
  @spec detect_system_pm() :: {:ok, atom()} | {:error, :none_found}
  def detect_system_pm do
    candidates = [:rpm, :deb, :pacman, :homebrew, :nix, :flatpak, :snap]

    case Enum.find(candidates, fn pm -> pm_available?(pm) end) do
      nil -> {:error, :none_found}
      pm -> {:ok, pm}
    end
  end

  defp pm_available?(pm) do
    {cmd, _, _} = query_command(pm) || {nil, nil, nil}
    cmd && System.find_executable(cmd) != nil
  end

  # Query commands: {command, args, output_parser}
  defp query_command(:deb) do
    # dpkg-query -W with no format outputs "package\tversion" by default
    {"dpkg-query", ["-W"], &parse_tab_separated/1}
  end

  defp query_command(:rpm) do
    # rpm -qa outputs name-version-release.arch by default
    # We parse that instead of using --queryformat (which requires {} braces
    # that SafeExec's shell validation rejects)
    {"rpm", ["-qa"], &parse_rpm_default/1}
  end

  defp query_command(:pacman) do
    {"pacman", ["-Q"], &parse_space_separated/1}
  end

  defp query_command(:homebrew) do
    {"brew", ["list", "--versions"], &parse_brew_list/1}
  end

  defp query_command(:nix) do
    {"nix-env", ["--query", "--installed"], &parse_nix_list/1}
  end

  defp query_command(:flatpak) do
    {"flatpak", ["list", "--columns=application,version"], &parse_tab_separated/1}
  end

  defp query_command(:snap) do
    {"snap", ["list"], &parse_snap_list/1}
  end

  defp query_command(:guix) do
    {"guix", ["package", "--list-installed"], &parse_tab_separated/1}
  end

  defp query_command(_), do: nil

  # Search commands: {command, args, output_parser}
  defp search_command(:deb, pkg) do
    {"apt-cache", ["show", pkg], &parse_apt_show/2}
  end

  defp search_command(:rpm, pkg) do
    {"dnf", ["info", "--available", pkg], &parse_dnf_info/2}
  end

  defp search_command(:pacman, pkg) do
    {"pacman", ["-Ss", pkg], &parse_pacman_search/2}
  end

  defp search_command(:homebrew, pkg) do
    {"brew", ["info", "--json=v2", pkg], &parse_brew_info/2}
  end

  defp search_command(:nix, pkg) do
    {"nix-env", ["-qaP", pkg], &parse_nix_search/2}
  end

  defp search_command(:flatpak, pkg) do
    {"flatpak", ["search", pkg], &parse_flatpak_search/2}
  end

  defp search_command(:snap, pkg) do
    {"snap", ["info", pkg], &parse_snap_info/2}
  end

  defp search_command(_, _), do: nil

  # Output parsers

  defp parse_tab_separated(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, "\t", parts: 2) do
        [name, version] -> %{name: String.trim(name), version: String.trim(version)}
        [name] -> %{name: String.trim(name), version: "unknown"}
      end
    end)
  end

  # RPM default output: name-version-release.arch (e.g., "bash-5.2.26-3.fc40.x86_64")
  # We split on the last two dashes to extract name and version
  defp parse_rpm_default(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      # Split from the right: name-version-release.arch
      # Strategy: find the last dash before a digit sequence
      case Regex.run(~r/^(.+)-(\d[^-]*)-[^-]+$/, line) do
        [_, name, version] ->
          %{name: name, version: version}

        _ ->
          # Fallback: split on first dash-digit
          case Regex.run(~r/^(.+?)-(\d.*)$/, line) do
            [_, name, rest] -> %{name: name, version: rest}
            _ -> %{name: String.trim(line), version: "unknown"}
          end
      end
    end)
  end

  defp parse_space_separated(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [name, version] -> %{name: String.trim(name), version: String.trim(version)}
        [name] -> %{name: String.trim(name), version: "unknown"}
      end
    end)
  end

  defp parse_brew_list(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/, parts: 2) do
        [name, versions] ->
          %{name: name, version: String.split(versions) |> List.last() || "unknown"}

        [name] ->
          %{name: name, version: "unknown"}
      end
    end)
  end

  defp parse_nix_list(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      # nix-env format: nixpkgs.package-name-1.2.3
      parts = String.split(line, ~r/\s+/)
      name = List.first(parts) || line

      # Try to extract version from the name (last dash-separated number group)
      case Regex.run(~r/^(.+)-(\d[\d.]*)$/, name) do
        [_, pkg, ver] -> %{name: pkg, version: ver}
        _ -> %{name: name, version: "unknown"}
      end
    end)
  end

  defp parse_snap_list(output) do
    output
    |> String.split("\n", trim: true)
    # Skip header line
    |> Enum.drop(1)
    |> Enum.map(fn line ->
      case String.split(line, ~r/\s+/) do
        [name, version | _] -> %{name: name, version: version}
        [name] -> %{name: name, version: "unknown"}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_apt_show(output, _package_name) do
    version =
      output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case String.split(line, ":", parts: 2) do
          ["Version", v] -> String.trim(v)
          _ -> nil
        end
      end)

    %{available: true, versions: if(version, do: [version], else: [])}
  end

  defp parse_dnf_info(output, _package_name) do
    version =
      output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        if String.starts_with?(String.trim(line), "Version") do
          case String.split(line, ":", parts: 2) do
            [_, v] -> String.trim(v)
            _ -> nil
          end
        end
      end)

    %{available: true, versions: if(version, do: [version], else: [])}
  end

  defp parse_pacman_search(output, _package_name) do
    versions =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case Regex.run(~r{/(\S+)\s+(\S+)}, line) do
          [_, _name, version] -> [version]
          _ -> []
        end
      end)

    %{available: versions != [], versions: versions}
  end

  defp parse_brew_info(output, _package_name) do
    case Jason.decode(output) do
      {:ok, %{"formulae" => [formula | _]}} ->
        versions = [formula["versions"]["stable"]] |> Enum.reject(&is_nil/1)
        %{available: true, versions: versions}

      _ ->
        %{available: false, versions: []}
    end
  end

  defp parse_nix_search(output, _package_name) do
    versions =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/-(\d[\d.]*)$/, line) do
          [_, v] -> [v]
          _ -> []
        end
      end)

    %{available: versions != [], versions: versions}
  end

  defp parse_flatpak_search(output, _package_name) do
    versions =
      output
      |> String.split("\n", trim: true)
      |> Enum.drop(1)
      |> Enum.flat_map(fn line ->
        parts = String.split(line, "\t")

        case Enum.at(parts, 1) do
          nil -> []
          v -> [String.trim(v)]
        end
      end)

    %{available: versions != [], versions: versions}
  end

  defp parse_snap_info(output, _package_name) do
    version =
      output
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case Regex.run(~r/^stable:\s+(\S+)/, String.trim(line)) do
          [_, v] -> v
          _ -> nil
        end
      end)

    %{available: version != nil, versions: if(version, do: [version], else: [])}
  end
end
