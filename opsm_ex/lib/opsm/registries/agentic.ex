# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Agentic do
  @moduledoc """
  Agentic registry adapter that delegates to HAR for package discovery.

  This adapter is used when a package cannot be found through conventional
  registries. It leverages hybrid-automation-router (HAR) agents to:

  - Search GitHub, GitLab, and other code hosting platforms
  - Scrape legacy project websites
  - Try multiple download mirrors
  - Assist users interactively when automation fails
  - Build packages from source

  See docs/har-integration.adoc for protocol details.
  """

  import Bitwise

  alias Opsm.HarQueue
  alias Opsm.Types.{ResolvedPackage, ManifestFormat}

  require Logger

  @doc """
  Fetch a package using agentic discovery via HAR.

  ## Parameters

  - `name`: Package name to search for
  - `hints`: Map of hints to guide the search:
    - `:language` - Programming language (e.g., "idris2", "ada")
    - `:version` - Desired version (default: "latest")
    - `:ecosystem` - Ecosystem type (e.g., "functional-programming")
    - `:search_hints` - List of search terms
    - `:common_domains` - List of likely hosting domains
    - `:file_patterns` - Patterns for manifest files (e.g., ["*.ipkg"])
    - `:build_commands` - Commands to build the package
    - `:maintainer` - Maintainer email for contact
    - `:last_known_url` - Last known download location

  ## Examples

      iex> Agentic.fetch_package("obscure-lib", %{
      ...>   language: "idris2",
      ...>   search_hints: ["idris2 obscure-lib", "obscure library"]
      ...> })
      {:ok, %ResolvedPackage{...}}

  """
  @spec fetch_package(String.t(), map()) ::
    {:ok, ResolvedPackage.t()} | {:error, term()}
  def fetch_package(name, hints \\ %{}) do
    task_id = generate_task_id()
    timeout = Map.get(hints, :timeout, 300_000)  # 5 minutes default

    Logger.info("Submitting agentic fetch task for #{name} (task_id: #{task_id})")

    task = build_task(task_id, name, hints)

    with {:ok, _} <- HarQueue.submit(task),
         {:ok, result} <- HarQueue.await_result(task_id, timeout: timeout) do
      parse_result(result)
    else
      {:error, :timeout} ->
        Logger.warning("Agentic fetch timed out for #{name} after #{timeout}ms")
        {:error, "HAR agent timeout - package not found within #{div(timeout, 1000)}s"}

      {:error, reason} ->
        Logger.error("Agentic fetch failed for #{name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Search functionality not implemented for agentic adapter.

  Agentic search would be too slow and resource-intensive for
  interactive use. Use conventional registries for search.
  """
  def search(_query, _opts \\ []) do
    {:error, "Search not supported by agentic adapter - use conventional registries"}
  end

  @doc """
  Check package existence via agentic discovery.

  Warning: This is slow as it triggers a full HAR agent search.
  Only use when package is known to be obscure/hard to find.
  """
  def exists?(name) do
    case fetch_package(name, %{timeout: 60_000}) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  List versions for a package.

  For agentic packages, version information may be incomplete.
  Returns versions discovered by HAR agents.
  """
  def versions(name) do
    case fetch_package(name) do
      {:ok, pkg} ->
        # Extract versions from raw_manifest if available
        raw = (pkg.manifest && pkg.manifest.raw_manifest) || %{}
        versions = raw["versions"] || [pkg.version]
        {:ok, versions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp generate_task_id do
    # Generate a UUID v4 using Elixir's built-in :crypto
    <<u0::32, u1::16, u2::16, u3::16, u4::48>> = :crypto.strong_rand_bytes(16)
    # Set version (4) and variant (2) bits according to RFC 4122
    u2 = (u2 &&& 0x0FFF) ||| 0x4000
    u3 = (u3 &&& 0x3FFF) ||| 0x8000

    :io_lib.format(
      "~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b",
      [u0, u1, u2, u3, u4]
    )
    |> IO.iodata_to_binary()
  end

  defp build_task(task_id, name, hints) do
    %{
      task_id: task_id,
      task_type: "package_fetch",
      submitted_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      timeout_seconds: div(Map.get(hints, :timeout, 300_000), 1000),
      package: %{
        name: name,
        version: Map.get(hints, :version, "latest"),
        language: Map.get(hints, :language, "unknown")
      },
      strategy: "agentic",
      hints: %{
        search_terms: Map.get(hints, :search_hints, [name]),
        common_domains: Map.get(hints, :common_domains, []),
        file_patterns: Map.get(hints, :file_patterns, []),
        maintainer: Map.get(hints, :maintainer),
        last_known_url: Map.get(hints, :last_known_url),
        build_commands: Map.get(hints, :build_commands, []),
        ecosystem: Map.get(hints, :ecosystem)
      } |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Map.new(),
      callback: %{
        url: callback_url(task_id),
        method: "POST",
        auth: "Bearer #{get_callback_token()}"
      }
    }
  end

  defp callback_url(task_id) do
    port = Application.get_env(:opsm, :har_callback_port, 4050)
    "http://localhost:#{port}/har/result/#{task_id}"
  end

  defp get_callback_token do
    # In production, use a secure token
    # For now, use a simple token
    Application.get_env(:opsm, :har_callback_token, "dev-token")
  end

  defp parse_result(%{"status" => "success"} = result) do
    loc = result["package_location"]
    meta = result["metadata"]
    disc = result["discovery"]
    verif = result["verification"]

    # Create manifest
    manifest = %ManifestFormat{
      name: meta["name"],
      version: meta["version"],
      description: meta["description"],
      license: meta["license"],
      repository: loc["url"],
      source_forth: :agentic,
      dependencies: parse_dependencies(meta["dependencies"]),
      dev_dependencies: %{},
      raw_manifest: %{
        "registry" => "agentic",
        "language" => result["package"]["language"],
        "discovery_method" => disc["method"],
        "confidence" => disc["confidence"],
        "location_type" => loc["type"],
        "commit_sha" => loc["commit_sha"],
        "subpath" => loc["subpath"],
        "digest" => verif["digest"],
        "manifest_file" => meta["manifest_file"],
        "alternatives" => disc["alternatives"]
      }
    }

    package = %ResolvedPackage{
      package: meta["name"],
      version: meta["version"],
      forth: :agentic,
      registry_url: "agentic://har-queue",
      tarball_url: build_download_url(loc),
      checksum: verif["digest"],
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }

    Logger.info("Agentic fetch succeeded: #{package.package}@#{package.version} " <>
                "(method: #{disc["method"]}, confidence: #{disc["confidence"]})")

    {:ok, package}
  end

  defp parse_result(%{"status" => "failure"} = result) do
    error = result["error"]
    task_id = result["task_id"]

    Logger.warning("Agentic fetch failed (task: #{task_id}): #{error["message"]}")
    Logger.debug("Attempts: #{inspect(error["attempts"])}")

    message = "#{error["message"]}\n\nSuggestions:\n" <>
              Enum.join(result["suggestions"] || [], "\n")

    {:error, message}
  end

  defp parse_result(other) do
    Logger.error("Invalid HAR result format: #{inspect(other)}")
    {:error, "Invalid response from HAR agents"}
  end

  defp parse_dependencies(deps) when is_list(deps) do
    Enum.reduce(deps, %{}, fn dep, acc ->
      Map.put(acc, dep, "*")
    end)
  end

  defp parse_dependencies(deps) when is_map(deps), do: deps
  defp parse_dependencies(_), do: %{}

  defp build_download_url(%{"type" => "git", "url" => url, "ref" => ref}) do
    "#{url}/archive/#{ref}.tar.gz"
  end

  defp build_download_url(%{"type" => "tarball", "url" => url}) do
    url
  end

  defp build_download_url(%{"type" => "source", "url" => url}) do
    url
  end

  defp build_download_url(_), do: nil
end
