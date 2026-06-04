# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
# cleanup.ex — Extended cleanup for desktop integration, services, and config.
#
# Handles platform-specific artifacts that the basic do_remove/1 doesn't touch:
#   - Desktop shortcuts (.desktop files on Linux, Start Menu on Windows)
#   - System services (systemd units, launchd plists)
#   - Config directories (~/.config/<app>, XDG)
#   - File associations and MIME types
#   - Autostart entries
#
# Part of the UX Manifesto "Uninstall (4 tiers)" requirement.
#

defmodule Opsm.Package.Cleanup do
  @moduledoc """
  Extended cleanup for package uninstallation.

  Called after the basic file removal in `Installer.do_remove/1`.
  Handles desktop integration artifacts that the basic removal doesn't touch.
  """

  require Logger

  @doc """
  Run full cleanup for a package. Returns a list of actions taken.
  """
  def cleanup(package_name, opts \\ []) do
    include_data = Keyword.get(opts, :include_data, false)
    secure = Keyword.get(opts, :secure, false)

    actions = []

    actions = actions ++ remove_desktop_shortcuts(package_name)
    actions = actions ++ remove_autostart(package_name)
    actions = actions ++ remove_systemd_units(package_name)
    actions = actions ++ remove_file_associations(package_name)

    if include_data do
      actions = actions ++ remove_config_dirs(package_name, secure)
      actions = actions ++ remove_data_dirs(package_name, secure)
      actions = actions ++ remove_cache_dirs(package_name)
    end

    actions
  end

  @doc """
  Remove .desktop files from XDG applications directory.
  """
  def remove_desktop_shortcuts(package_name) do
    xdg_data = System.get_env("XDG_DATA_HOME", Path.join(System.user_home!(), ".local/share"))
    desktop_file = Path.join([xdg_data, "applications", "#{package_name}.desktop"])

    if File.exists?(desktop_file) do
      case File.rm(desktop_file) do
        :ok ->
          # Update desktop database
          System.cmd("update-desktop-database",
            [Path.join(xdg_data, "applications")],
            stderr_to_stdout: true
          )
          Logger.info("Removed desktop shortcut: #{desktop_file}")
          [{:removed, :desktop_shortcut, desktop_file}]

        {:error, reason} ->
          Logger.warning("Failed to remove desktop shortcut #{desktop_file}: #{reason}")
          [{:failed, :desktop_shortcut, desktop_file, reason}]
      end
    else
      []
    end
  end

  @doc """
  Remove autostart entries from XDG autostart directory.
  """
  def remove_autostart(package_name) do
    xdg_config = System.get_env("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
    autostart_file = Path.join([xdg_config, "autostart", "#{package_name}.desktop"])

    if File.exists?(autostart_file) do
      case File.rm(autostart_file) do
        :ok ->
          Logger.info("Removed autostart entry: #{autostart_file}")
          [{:removed, :autostart, autostart_file}]

        {:error, reason} ->
          Logger.warning("Failed to remove autostart #{autostart_file}: #{reason}")
          [{:failed, :autostart, autostart_file, reason}]
      end
    else
      []
    end
  end

  @doc """
  Remove systemd user units for the package.
  """
  def remove_systemd_units(package_name) do
    xdg_config = System.get_env("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
    systemd_dir = Path.join([xdg_config, "systemd", "user"])

    actions = []

    for ext <- [".service", ".timer", ".socket"] do
      unit_file = Path.join(systemd_dir, "#{package_name}#{ext}")

      if File.exists?(unit_file) do
        # Stop and disable before removing
        System.cmd("systemctl", ["--user", "stop", "#{package_name}#{ext}"],
          stderr_to_stdout: true
        )
        System.cmd("systemctl", ["--user", "disable", "#{package_name}#{ext}"],
          stderr_to_stdout: true
        )

        case File.rm(unit_file) do
          :ok ->
            Logger.info("Removed systemd unit: #{unit_file}")
            actions ++ [{:removed, :systemd_unit, unit_file}]

          {:error, reason} ->
            Logger.warning("Failed to remove systemd unit #{unit_file}: #{reason}")
            actions ++ [{:failed, :systemd_unit, unit_file, reason}]
        end
      else
        actions
      end
    end

    # Reload systemd daemon if we removed anything
    if actions != [] do
      System.cmd("systemctl", ["--user", "daemon-reload"], stderr_to_stdout: true)
    end

    actions
  end

  @doc """
  Remove MIME type associations for the package.
  """
  def remove_file_associations(package_name) do
    xdg_data = System.get_env("XDG_DATA_HOME", Path.join(System.user_home!(), ".local/share"))
    mime_file = Path.join([xdg_data, "mime", "packages", "#{package_name}.xml"])

    if File.exists?(mime_file) do
      case File.rm(mime_file) do
        :ok ->
          System.cmd("update-mime-database", [Path.join(xdg_data, "mime")],
            stderr_to_stdout: true
          )
          Logger.info("Removed MIME associations: #{mime_file}")
          [{:removed, :mime_type, mime_file}]

        {:error, reason} ->
          [{:failed, :mime_type, mime_file, reason}]
      end
    else
      []
    end
  end

  @doc """
  Remove config directories. If secure=true, overwrite files before deletion.
  """
  def remove_config_dirs(package_name, secure \\ false) do
    xdg_config = System.get_env("XDG_CONFIG_HOME", Path.join(System.user_home!(), ".config"))
    config_dir = Path.join(xdg_config, package_name)

    if File.dir?(config_dir) do
      if secure, do: secure_wipe_dir(config_dir)

      case File.rm_rf(config_dir) do
        {:ok, _} ->
          Logger.info("Removed config directory: #{config_dir}")
          [{:removed, :config_dir, config_dir}]

        {:error, reason, path} ->
          [{:failed, :config_dir, path, reason}]
      end
    else
      []
    end
  end

  @doc """
  Remove data directories.
  """
  def remove_data_dirs(package_name, secure \\ false) do
    xdg_data = System.get_env("XDG_DATA_HOME", Path.join(System.user_home!(), ".local/share"))
    data_dir = Path.join(xdg_data, package_name)

    if File.dir?(data_dir) do
      if secure, do: secure_wipe_dir(data_dir)

      case File.rm_rf(data_dir) do
        {:ok, _} ->
          Logger.info("Removed data directory: #{data_dir}")
          [{:removed, :data_dir, data_dir}]

        {:error, reason, path} ->
          [{:failed, :data_dir, path, reason}]
      end
    else
      []
    end
  end

  @doc """
  Remove cache directories.
  """
  def remove_cache_dirs(package_name) do
    xdg_cache = System.get_env("XDG_CACHE_HOME", Path.join(System.user_home!(), ".cache"))
    cache_dir = Path.join(xdg_cache, package_name)

    if File.dir?(cache_dir) do
      case File.rm_rf(cache_dir) do
        {:ok, _} ->
          Logger.info("Removed cache directory: #{cache_dir}")
          [{:removed, :cache_dir, cache_dir}]

        {:error, reason, path} ->
          [{:failed, :cache_dir, path, reason}]
      end
    else
      []
    end
  end

  @doc """
  Generate a cleanup report showing what was removed.
  """
  def format_report(actions) do
    if actions == [] do
      "  No additional cleanup needed."
    else
      actions
      |> Enum.map(fn
        {:removed, type, path} -> "  [OK] Removed #{type}: #{path}"
        {:failed, type, path, reason} -> "  [FAIL] #{type}: #{path} (#{reason})"
      end)
      |> Enum.join("\n")
    end
  end

  # ── Private ──

  defp secure_wipe_dir(dir) do
    # Overwrite file contents with zeros before deletion
    Path.wildcard(Path.join(dir, "**/*"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.each(fn file ->
      case File.stat(file) do
        {:ok, %{size: size}} when size > 0 ->
          zeros = :binary.copy(<<0>>, size)
          File.write(file, zeros)

        _ ->
          :ok
      end
    end)
  end
end
