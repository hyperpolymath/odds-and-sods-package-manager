# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.DenoX do
  @moduledoc """
  Deno Third Party Modules (deno.land/x) Registry API client.
  https://apiland.deno.dev/v2/modules
  Provides access to the Deno third-party module registry (deno.land/x).
  Uses the apiland v2 REST API for module metadata and version listings.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://apiland.deno.dev/v2/modules"
  @cdn_url "https://deno.land/x"

  @doc """
  Fetch module metadata from the Deno third-party registry.
  The `name` is the module name (e.g., "oak", "cliffy", "fresh").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        resolved_version =
          if version == "latest" do
            body["latest_version"] || body["latestVersion"]
          else
            version
          end

        case resolved_version do
          nil -> {:error, :not_found}
          ver -> {:ok, parse_module(body, ver)}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Deno registry API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for modules on deno.land/x.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}?query=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        entries =
          Enum.map(results, fn mod ->
            %{
              name: mod["name"],
              version: mod["latest_version"] || mod["latestVersion"],
              description: mod["description"] || ""
            }
          end)

        {:ok, entries}

      {:ok, %{"items" => items}} when is_list(items) ->
        entries =
          Enum.map(items, fn mod ->
            %{
              name: mod["name"],
              version: mod["latest_version"] || mod["latestVersion"],
              description: mod["description"] || ""
            }
          end)

        {:ok, entries}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Deno module search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a module exists on deno.land/x.
  """
  def exists?(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all available versions of a Deno third-party module.
  """
  def versions(name) do
    url = "#{@api_url}/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, versions}

      {:ok, %{"versions" => versions}} when is_map(versions) ->
        {:ok, Map.keys(versions) |> Enum.sort(&version_compare/2)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Parsers
  # ---------------------------------------------------------------------------

  defp parse_module(json, version) do
    mod_name = json["name"]
    repo_url = extract_repo(json)

    %ResolvedPackage{
      package: mod_name,
      version: version,
      forth: :deno_x,
      registry_url: "#{@cdn_url}/#{mod_name}@#{version}",
      tarball_url: build_tarball_url(mod_name, version, repo_url),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: mod_name,
        version: version,
        description: json["description"],
        license: nil,
        homepage: "#{@cdn_url}/#{mod_name}",
        repository: repo_url,
        authors: extract_owner(json),
        keywords: json["tags"] || [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :deno_x,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_repo(json) do
    case json do
      %{"upload_options" => %{"repository" => repo}} ->
        "https://github.com/#{repo}"

      %{"repo" => repo} when is_binary(repo) ->
        repo

      %{"repository" => %{"url" => url}} ->
        url

      _ ->
        nil
    end
  end

  defp extract_owner(json) do
    case json do
      %{"upload_options" => %{"repository" => repo}} ->
        [repo |> String.split("/") |> List.first()]

      %{"owner" => owner} when is_binary(owner) ->
        [owner]

      _ ->
        []
    end
  end

  defp build_tarball_url(name, version, repo_url) do
    case repo_url do
      "https://github.com/" <> repo ->
        "https://github.com/#{repo}/archive/refs/tags/#{version}.tar.gz"

      _ ->
        "#{@cdn_url}/#{name}@#{version}/mod.ts"
    end
  end

  defp version_compare(a, b) do
    Version.compare(normalize_version(a), normalize_version(b)) == :gt
  rescue
    _ -> a > b
  end

  defp normalize_version(v) do
    parts =
      v
      |> String.replace(~r/^v/, "")
      |> String.split("-")
      |> List.first()
      |> String.split(".")

    case length(parts) do
      1 -> Enum.at(parts, 0) <> ".0.0"
      2 -> Enum.join(parts, ".") <> ".0"
      _ -> Enum.join(parts, ".")
    end
  end
end
