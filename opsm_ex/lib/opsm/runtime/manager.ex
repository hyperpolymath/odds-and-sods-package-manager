# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# OPSM Runtime Manager
# ====================
# Coordinates install, list, update, remove operations for OPSM-managed
# runtime tools (the asdf replacement layer).
#
# Layout on disk:
#   ~/.opsm/runtimes/<tool>/<version>/   — installed binaries
#   ~/.opsm/runtimes/.active             — TOML: active version per tool
#   ~/.opsm/runtimes/.plugins            — Nickel plugin cache (evaluated JSON)

defmodule Opsm.Runtime.Manager do
  @moduledoc """
  High-level operations for managing runtime tools installed by OPSM.

  Provides `list_installed/0`, `check_updates/0`, `install/2`, `remove/1`,
  `which/1`, `latest_version/1`, and `current_version/1`.  The CLI delegates
  all runtime subcommands here.
  """

  alias Opsm.Runtime.UrlHandler
  alias Opsm.Runtime.SourceBuilder
  alias Opsm.Verified.Http, as: VerifiedHttp

  @runtimes_dir Path.expand("~/.opsm/runtimes")
  @active_file  Path.join(@runtimes_dir, ".active")
  @plugins_dir  Path.join(@runtimes_dir, ".plugins")

  # ---------------------------------------------------------------------------
  # Listing
  # ---------------------------------------------------------------------------

  @doc """
  List all installed runtime tools and their versions.

  Returns `[%{name: tool, version: version, active: bool}]`.
  """
  def list_installed do
    case File.ls(@runtimes_dir) do
      {:ok, entries} ->
        active = load_active()

        entries
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.flat_map(fn tool_dir ->
          tool_path = Path.join(@runtimes_dir, tool_dir)
          case File.ls(tool_path) do
            {:ok, versions} ->
              active_ver = Map.get(active, tool_dir)
              Enum.map(versions, fn ver ->
                %{name: tool_dir, version: ver, active: ver == active_ver}
              end)
            _ -> []
          end
        end)
        |> Enum.sort_by(& &1.name)

      _ -> []
    end
  end

  @doc """
  List only the active (current) version per installed tool.

  Returns `[{tool_name, version}]`.
  """
  def list_active do
    active = load_active()
    # Only include tools that are actually installed
    installed_tools =
      case File.ls(@runtimes_dir) do
        {:ok, entries} ->
          entries |> Enum.reject(&String.starts_with?(&1, ".")) |> MapSet.new()
        _ -> MapSet.new()
      end

    active
    |> Enum.filter(fn {tool, _ver} -> MapSet.member?(installed_tools, tool) end)
    |> Enum.sort_by(fn {tool, _} -> tool end)
  end

  # ---------------------------------------------------------------------------
  # Version querying
  # ---------------------------------------------------------------------------

  @doc """
  Return the currently active version for a tool, or "none" if not installed.
  """
  def current_version(tool) do
    active = load_active()
    Map.get(active, tool, "none")
  end

  @doc """
  Fetch the latest available version for a tool from its upstream source.

  Returns `{:ok, version_string}` or `{:error, reason}`.
  """
  def latest_version(tool) do
    with {:ok, plugin} <- load_plugin(tool),
         {:ok, versions} <- fetch_versions(tool, plugin) do
      case versions do
        [latest | _] -> {:ok, latest}
        [] -> {:error, :no_versions_found}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Update checking
  # ---------------------------------------------------------------------------

  @doc """
  Check all installed tools for available updates.

  Returns `{:ok, [%{name:, current:, latest:}]}`.
  """
  def check_updates do
    installed = list_installed()
    # Deduplicate — for each tool, only consider the active version
    active = load_active()

    tools_to_check =
      installed
      |> Enum.filter(fn t -> t.active or Map.get(active, t.name) == nil end)
      |> Enum.uniq_by(& &1.name)

    updates =
      tools_to_check
      |> Enum.flat_map(fn %{name: tool, version: current} ->
        case latest_version(tool) do
          {:ok, latest} when latest != current ->
            [%{name: tool, current: current, latest: latest}]
          _ ->
            []
        end
      end)

    {:ok, updates}
  end

  # ---------------------------------------------------------------------------
  # Install
  # ---------------------------------------------------------------------------

  @doc """
  Install a specific version of a tool.

  Delegates to `SourceBuilder` for build-from-source / delegate-to-manager
  strategies, or performs the download+extract for prebuilt binaries.

  Returns `:ok` or `{:error, reason}`.
  """
  def install(tool, version) do
    install_dir = Path.join([@runtimes_dir, tool, version])

    if File.dir?(install_dir) do
      # Already installed — just set as active
      set_active(tool, version)
      :ok
    else
      with {:ok, plugin} <- load_plugin(tool) do
        strategy = get_in(plugin, ["install", "strategy"]) ||
                   get_in(plugin, [:install, :strategy])

        result =
          case to_string(strategy) do
            s when s in ["BuildFromSource", "DelegateToManager", "Both"] ->
              SourceBuilder.install(plugin, version)
            _ ->
              install_prebuilt(tool, version, plugin, install_dir)
          end

        case result do
          :ok ->
            set_active(tool, version)
            :ok
          error ->
            error
        end
      end
    end
  end

  @doc """
  Install runtime tools from the `[runtime]` section of an opsm.toml file.

  Returns `{:ok, [{tool, version}]}` for the resolved pins, or `{:error, reason}`.
  """
  def install_from_manifest(path) do
    case File.read(path) do
      {:ok, content} ->
        pins = parse_runtime_section(content)
        {:ok, pins}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Remove
  # ---------------------------------------------------------------------------

  @doc """
  Remove all installed versions of a tool.
  """
  def remove(tool) do
    tool_dir = Path.join(@runtimes_dir, tool)

    # File.rm_rf returns {:ok, []} for non-existent paths, so we must
    # check existence explicitly before removal.
    if File.dir?(tool_dir) do
      case File.rm_rf(tool_dir) do
        {:ok, _} ->
          active = load_active()
          write_active(Map.delete(active, tool))
          :ok
        {:error, reason, _} ->
          {:error, reason}
      end
    else
      {:error, :not_installed}
    end
  end

  # ---------------------------------------------------------------------------
  # Which
  # ---------------------------------------------------------------------------

  @doc """
  Return the path to the active binary for a tool.
  """
  def which(tool) do
    case current_version(tool) do
      "none" -> {:error, :not_installed}
      version ->
        bin_dir = Path.join([@runtimes_dir, tool, version, "bin"])
        {:ok, Path.join(bin_dir, tool)}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Load the .active TOML file (simple key=value format, no dependencies)
  defp load_active do
    case File.read(@active_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [k, v] -> Map.put(acc, String.trim(k), String.trim(v))
            _ -> acc
          end
        end)
      _ -> %{}
    end
  end

  defp write_active(active_map) do
    File.mkdir_p!(Path.dirname(@active_file))
    content =
      active_map
      |> Enum.map(fn {k, v} -> "#{k} = #{v}" end)
      |> Enum.join("\n")
    File.write!(@active_file, content <> "\n")
  end

  defp set_active(tool, version) do
    active = load_active()
    write_active(Map.put(active, tool, version))
  end

  # Load a plugin's evaluated JSON from the plugin cache or evaluate on the fly.
  # Falls back to a minimal stub for tools that have no plugin definition yet.
  defp load_plugin(tool) do
    cached = Path.join(@plugins_dir, "#{tool}.json")

    if File.exists?(cached) do
      case Jason.decode(File.read!(cached)) do
        {:ok, plugin} -> {:ok, plugin}
        _ -> {:error, {:invalid_plugin_cache, tool}}
      end
    else
      # Try evaluating the Nickel plugin directly
      plugin_ncl = find_plugin_ncl(tool)
      case plugin_ncl do
        nil ->
          {:error, {:no_plugin, tool}}
        path ->
          case System.cmd("nickel", ["export", "--format", "json", path], stderr_to_stdout: true) do
            {json_str, 0} ->
              case Jason.decode(json_str) do
                {:ok, plugin} ->
                  # Cache for next time
                  File.mkdir_p!(@plugins_dir)
                  File.write!(cached, json_str)
                  {:ok, plugin}
                err -> {:error, {:json_decode, err}}
              end
            {err_str, _} ->
              {:error, {:nickel_eval, err_str}}
          end
      end
    end
  end

  @plugin_search_dirs [
    # Relative to the OPSM install — resolved at runtime
    Path.expand("../runtime/core", :code.priv_dir(:opsm)),
    Path.expand("~/.opsm/plugins/core"),
  ]

  defp find_plugin_ncl(tool) do
    Enum.find_value(@plugin_search_dirs, fn dir ->
      path = Path.join(dir, "#{tool}.ncl")
      if File.exists?(path), do: path
    end)
  end

  # Fetch version list from the plugin's version_source
  defp fetch_versions(tool, plugin) do
    url_handler = plugin["url_handler"] || plugin[:url_handler]
    version_source = plugin["version_source"] || plugin[:version_source]

    cond do
      url_handler != nil ->
        UrlHandler.versions(tool, url_handler)

      to_string(version_source) in ["GitHubReleases", "GitHubTags"] ->
        fetch_github_versions(plugin)

      true ->
        {:error, {:unsupported_version_source, version_source}}
    end
  end

  defp fetch_github_versions(plugin) do
    repo = plugin["repository"] || plugin[:repository]
    # Extract "owner/repo" from full URL
    github_path = repo |> String.replace("https://github.com/", "")
    api_url = "https://api.github.com/repos/#{github_path}/releases"

    case VerifiedHttp.get_json(api_url, receive_timeout: 10_000) do
      {:ok, releases} when is_list(releases) ->
        versions =
          releases
          |> Enum.map(fn r -> r["tag_name"] || r["name"] end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&String.trim_leading(&1, "v"))
          |> Enum.sort(:desc)
        {:ok, versions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Install a prebuilt binary by downloading and extracting the archive
  defp install_prebuilt(tool, version, plugin, install_dir) do
    platform = detect_platform()
    url_handler = plugin["url_handler"] || plugin[:url_handler]

    with {:ok, url} <- resolve_archive_url(tool, version, platform, plugin, url_handler),
         {:ok, archive_path} <- download_archive(url),
         :ok <- extract_archive(archive_path, install_dir, plugin) do
      :ok
    end
  end

  defp detect_platform do
    {uname_s, 0} = System.cmd("uname", ["-s"])
    {uname_m, 0} = System.cmd("uname", ["-m"])
    os = uname_s |> String.trim() |> String.downcase()
    arch = uname_m |> String.trim()

    case {os, arch} do
      {"linux", "x86_64"}  -> :linux_amd64
      {"linux", "aarch64"} -> :linux_arm64
      {"darwin", "x86_64"} -> :darwin_amd64
      {"darwin", "arm64"}  -> :darwin_arm64
      _other -> :linux_amd64
    end
  end

  defp resolve_archive_url(tool, version, platform, _plugin, url_handler)
       when not is_nil(url_handler) do
    UrlHandler.archive_url(tool, version, platform, url_handler)
  end

  defp resolve_archive_url(_tool, version, platform, plugin, nil) do
    # Fall back to archive_name_template from the platforms list
    platforms = get_in(plugin, ["install", "platforms"]) ||
                get_in(plugin, [:install, :platforms]) || []

    platform_str = Atom.to_string(platform)
    entry = Enum.find(platforms, fn p ->
      p_str = to_string(p["platform"] || p[:platform] || "")
      String.downcase(p_str) == String.downcase(platform_str)
    end)

    case entry do
      nil -> {:error, {:unsupported_platform, platform}}
      e ->
        template = e["archive_name_template"] || e[:archive_name_template]
        repo = plugin["repository"] || plugin[:repository]
        filename = String.replace(template, "{{version}}", version)
        url = "#{repo}/releases/download/v#{version}/#{filename}"
        {:ok, url}
    end
  end

  defp download_archive(url) do
    cache_dir = Path.expand("~/.opsm/download-cache")
    File.mkdir_p!(cache_dir)
    filename = url |> String.split("/") |> List.last()
    dest = Path.join(cache_dir, filename)

    if File.exists?(dest) do
      {:ok, dest}
    else
      # Use Req (via VerifiedHttp.get/2) with streaming to avoid loading the
      # entire archive into memory.  Falls back to :httpc if Req is unavailable.
      case VerifiedHttp.get(url, receive_timeout: 120_000, into: File.stream!(dest)) do
        {:ok, _} -> {:ok, dest}
        {:error, reason} ->
          File.rm(dest)
          {:error, {:download_failed, reason}}
      end
    end
  end

  defp extract_archive(archive_path, install_dir, plugin) do
    strip = get_in(plugin, ["install", "strip_components"]) ||
            get_in(plugin, [:install, :strip_components]) || 1

    File.mkdir_p!(install_dir)

    cond do
      String.ends_with?(archive_path, ".tar.xz") ->
        {_, 0} = System.cmd("tar", ["-xJf", archive_path, "--strip-components=#{strip}", "-C", install_dir])
        :ok
      String.ends_with?(archive_path, ".tar.gz") ->
        {_, 0} = System.cmd("tar", ["-xzf", archive_path, "--strip-components=#{strip}", "-C", install_dir])
        :ok
      String.ends_with?(archive_path, ".zip") ->
        {_, 0} = System.cmd("unzip", ["-q", archive_path, "-d", install_dir])
        :ok
      true ->
        # Raw binary — just make executable and put in bin/
        bin_dir = Path.join(install_dir, "bin")
        File.mkdir_p!(bin_dir)
        dest = Path.join(bin_dir, Path.basename(archive_path))
        File.copy!(archive_path, dest)
        File.chmod!(dest, 0o755)
        :ok
    end
  end

  # Parse the [runtime] section from an opsm.toml file into [{tool, version}]
  defp parse_runtime_section(content) do
    in_runtime_section =
      content
      |> String.split("\n")
      |> Enum.reduce({false, []}, fn line, {in_section, acc} ->
        stripped = String.trim(line)
        cond do
          stripped == "[runtime]" ->
            {true, acc}
          String.starts_with?(stripped, "[") and in_section ->
            {false, acc}
          in_section and String.contains?(stripped, "=") ->
            [tool, version] = String.split(stripped, "=", parts: 2)
            pair = {String.trim(tool), String.trim(version) |> String.trim("\"")}
            {true, [pair | acc]}
          true ->
            {in_section, acc}
        end
      end)

    elem(in_runtime_section, 1) |> Enum.reverse()
  end
end
