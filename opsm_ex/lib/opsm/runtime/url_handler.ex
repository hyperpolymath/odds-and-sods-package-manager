# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Runtime.UrlHandler do
  @moduledoc """
  Custom URL handler dispatch for runtime plugins that cannot use the
  default GitHub/GitLab Releases API.

  Tools like Zig, Julia, Go, Node.js, and Dart publish via their own
  infrastructure (custom JSON indices, S3 buckets, googleapis).  This
  module reads the `url_handler` field from a Nickel plugin definition
  and resolves version lists and archive URLs accordingly.

  ## Architecture

  Each Nickel plugin may declare an optional `url_handler` map:

      url_handler = {
        versions_url = "https://ziglang.org/download/index.json",
        version_key_pattern = "^[0-9]+\\.[0-9]+\\.[0-9]+$",
        archive_url_template = "https://ziglang.org/download/{{version}}/zig-{{zig_platform}}-{{version}}.tar.xz",
      }

  `versions/1` fetches the `versions_url`, extracts version strings
  matching `version_key_pattern`, and returns them sorted.

  `archive_url/3` resolves the `archive_url_template` with tool-specific
  platform variable substitution.

  ## Platform variables

  Each tool family has its own naming scheme.  The handler normalises
  the OPSM platform atom (e.g. `:linux_amd64`) to the upstream naming:

  | Tool      | OS key            | Arch key             |
  |-----------|-------------------|----------------------|
  | zig       | `linux`/`macos`   | `x86_64`/`aarch64`  |
  | julia     | `linux`/`mac`     | `x64`/`aarch64`     |
  | golang    | `linux`/`darwin`  | `amd64`/`arm64`     |
  | nodejs    | `linux`/`darwin`  | `x64`/`arm64`       |
  | dart      | `linux`/`macos`   | `x64`/`arm64`       |
  | nim       | `linux`/`macos`   | `x64`/`arm64`       |
  | kubectl   | `linux`/`darwin`  | `amd64`/`arm64`     |
  """

  alias Opsm.Verified.Http, as: VerifiedHttp

  # ---------------------------------------------------------------------------
  # Version listing
  # ---------------------------------------------------------------------------

  @doc """
  Fetch available versions for a tool using its custom URL handler.

  Returns `{:ok, [version_string]}` sorted newest-first, or
  `{:error, reason}` on failure.
  """
  def versions(tool_name, url_handler) do
    versions_url = url_handler["versions_url"] || url_handler[:versions_url]
    pattern = url_handler["version_key_pattern"] || url_handler[:version_key_pattern]

    case VerifiedHttp.get_json(versions_url, receive_timeout: 15_000) do
      {:ok, body} ->
        versions = extract_versions(body, pattern, tool_name)
        {:ok, versions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Archive URL resolution
  # ---------------------------------------------------------------------------

  @doc """
  Resolve the download URL for a specific version and platform.

  Returns `{:ok, url_string}` or `{:error, :unsupported_platform}`.
  """
  def archive_url(tool_name, version, platform, url_handler) do
    template = url_handler["archive_url_template"] || url_handler[:archive_url_template]

    case platform_vars(tool_name, platform) do
      {:ok, vars} ->
        url = expand_template(template, Map.merge(vars, %{"version" => version}))
        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Version extraction — handles JSON objects (keyed by version) and arrays
  # ---------------------------------------------------------------------------

  # Public for testing only — not part of the external API.
  @doc false
  def process_versions_body(body, pattern, tool_name), do: extract_versions(body, pattern, tool_name)

  defp extract_versions(body, pattern, tool_name) when is_map(body) do
    # JSON object: keys are version strings (e.g., Zig's index.json)
    body
    |> Map.keys()
    |> filter_versions(pattern)
    |> sort_versions(tool_name)
  end

  defp extract_versions(body, pattern, tool_name) when is_list(body) do
    # JSON array: look for "version" field in each element (Node.js, Go)
    body
    |> Enum.map(fn
      %{"version" => v} -> v
      v when is_binary(v) -> v
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> filter_versions(pattern)
    |> sort_versions(tool_name)
  end

  defp filter_versions(versions, nil), do: versions
  defp filter_versions(versions, pattern) do
    {:ok, re} = Regex.compile(pattern)
    Enum.filter(versions, &Regex.match?(re, &1))
  end

  defp sort_versions(versions, _tool_name) do
    # Sort descending (newest first) — best-effort semver sort
    Enum.sort(versions, fn a, b ->
      parse_ver(a) >= parse_ver(b)
    end)
  end

  defp parse_ver(v) do
    # Strip leading "v" or "go" prefixes, then parse as semver
    cleaned = v |> String.trim_leading("v") |> String.trim_leading("go")
    parts =
      cleaned
      |> String.split(".")
      |> Enum.map(&Integer.parse/1)
      |> Enum.map(fn
        {n, _} -> n
        :error -> 0
      end)
    List.to_tuple(parts)
  rescue
    _ -> {0, 0, 0}
  end

  # ---------------------------------------------------------------------------
  # Platform variable resolution — tool-specific naming conventions
  # ---------------------------------------------------------------------------

  defp platform_vars("zig", platform) do
    case platform do
      :linux_amd64  -> {:ok, %{"zig_platform" => "linux-x86_64"}}
      :linux_arm64  -> {:ok, %{"zig_platform" => "linux-aarch64"}}
      :darwin_amd64 -> {:ok, %{"zig_platform" => "macos-x86_64"}}
      :darwin_arm64 -> {:ok, %{"zig_platform" => "macos-aarch64"}}
      :windows_amd64 -> {:ok, %{"zig_platform" => "windows-x86_64"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("julia", platform) do
    case platform do
      :linux_amd64  -> {:ok, %{"julia_os" => "linux", "julia_arch" => "x64",
                               "julia_arch_suffix" => ".tar.gz", "julia_minor" => "1"}}
      :linux_arm64  -> {:ok, %{"julia_os" => "linux", "julia_arch" => "aarch64",
                               "julia_arch_suffix" => ".tar.gz", "julia_minor" => "1"}}
      :darwin_amd64 -> {:ok, %{"julia_os" => "mac", "julia_arch" => "x64",
                               "julia_arch_suffix" => ".dmg", "julia_minor" => "1"}}
      :darwin_arm64 -> {:ok, %{"julia_os" => "mac", "julia_arch" => "aarch64",
                               "julia_arch_suffix" => ".dmg", "julia_minor" => "1"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("golang", platform) do
    case platform do
      :linux_amd64   -> {:ok, %{"go_os" => "linux",   "go_arch" => "amd64", "go_version" => "go{{version}}"}}
      :linux_arm64   -> {:ok, %{"go_os" => "linux",   "go_arch" => "arm64", "go_version" => "go{{version}}"}}
      :darwin_amd64  -> {:ok, %{"go_os" => "darwin",  "go_arch" => "amd64", "go_version" => "go{{version}}"}}
      :darwin_arm64  -> {:ok, %{"go_os" => "darwin",  "go_arch" => "arm64", "go_version" => "go{{version}}"}}
      :windows_amd64 -> {:ok, %{"go_os" => "windows", "go_arch" => "amd64", "go_version" => "go{{version}}"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("nodejs", platform) do
    case platform do
      :linux_amd64   -> {:ok, %{"node_os" => "linux",   "node_arch" => "x64"}}
      :linux_arm64   -> {:ok, %{"node_os" => "linux",   "node_arch" => "arm64"}}
      :darwin_amd64  -> {:ok, %{"node_os" => "darwin",  "node_arch" => "x64"}}
      :darwin_arm64  -> {:ok, %{"node_os" => "darwin",  "node_arch" => "arm64"}}
      :windows_amd64 -> {:ok, %{"node_os" => "win",     "node_arch" => "x64"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("dart", platform) do
    case platform do
      :linux_amd64   -> {:ok, %{"dart_os" => "linux",   "dart_arch" => "x64"}}
      :linux_arm64   -> {:ok, %{"dart_os" => "linux",   "dart_arch" => "arm64"}}
      :darwin_amd64  -> {:ok, %{"dart_os" => "macos",   "dart_arch" => "x64"}}
      :darwin_arm64  -> {:ok, %{"dart_os" => "macos",   "dart_arch" => "arm64"}}
      :windows_amd64 -> {:ok, %{"dart_os" => "windows", "dart_arch" => "x64"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("nim", platform) do
    # Nim archives: nim-2.0.2_linux_x64.tar.xz or nim-2.0.2_macos_arm64.tar.xz
    case platform do
      :linux_amd64  -> {:ok, %{"nim_os" => "linux",  "nim_arch" => "x64"}}
      :linux_arm64  -> {:ok, %{"nim_os" => "linux",  "nim_arch" => "arm64"}}
      :darwin_amd64 -> {:ok, %{"nim_os" => "macos",  "nim_arch" => "x64"}}
      :darwin_arm64 -> {:ok, %{"nim_os" => "macos",  "nim_arch" => "arm64"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars("kubectl", platform) do
    # kubectl binary at: dl.k8s.io/release/v{{version}}/bin/linux/amd64/kubectl
    case platform do
      :linux_amd64   -> {:ok, %{"kubectl_os" => "linux",   "kubectl_arch" => "amd64"}}
      :linux_arm64   -> {:ok, %{"kubectl_os" => "linux",   "kubectl_arch" => "arm64"}}
      :darwin_amd64  -> {:ok, %{"kubectl_os" => "darwin",  "kubectl_arch" => "amd64"}}
      :darwin_arm64  -> {:ok, %{"kubectl_os" => "darwin",  "kubectl_arch" => "arm64"}}
      :windows_amd64 -> {:ok, %{"kubectl_os" => "windows", "kubectl_arch" => "amd64"}}
      _ -> {:error, :unsupported_platform}
    end
  end

  defp platform_vars(_tool, _platform), do: {:error, :no_url_handler}

  # ---------------------------------------------------------------------------
  # Template expansion
  # ---------------------------------------------------------------------------

  defp expand_template(template, vars) do
    Enum.reduce(vars, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
end
