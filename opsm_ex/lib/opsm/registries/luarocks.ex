# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.LuaRocks do
  @moduledoc """
  LuaRocks registry API client.
  https://luarocks.org/
  Uses the LuaRocks public repository API.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @registry_url "https://luarocks.org"

  @doc """
  Fetch package metadata from LuaRocks.
  """
  def fetch_package(name, version \\ "latest") do
    target_version = if version == "latest" do
      fetch_latest_version(name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        # Try to fetch rockspec file
        rockspec_url = "#{@registry_url}/manifests/#{name}/#{name}-#{ver}.rockspec"
        case VerifiedHttp.get(rockspec_url, receive_timeout: 10_000) do
          {:ok, %{body: body}} when is_binary(body) ->
            parse_rockspec(name, ver, body)

          {:ok, body} when is_binary(body) ->
            parse_rockspec(name, ver, body)

          {:error, :not_found} ->
            # Fallback: use module info endpoint
            fetch_from_module_info(name, ver)

          {:error, %{status: 404}} ->
            fetch_from_module_info(name, ver)

          {:error, %{status: status}} ->
            {:error, "LuaRocks returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(name) do
    # Use the modules API to get latest version
    url = "#{@registry_url}/modules/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        # Extract latest version from module info
        extract_latest_version(body)

      _ ->
        # Fallback: try search API
        case search(name, limit: 1) do
          {:ok, [%{version: version} | _]} -> version
          _ -> nil
        end
    end
  end

  defp extract_latest_version(module_info) do
    # LuaRocks module API returns versions in various formats
    # Try different possible structures
    cond do
      is_map(module_info) and Map.has_key?(module_info, "latest_version") ->
        module_info["latest_version"]

      is_map(module_info) and Map.has_key?(module_info, "versions") ->
        case module_info["versions"] do
          [latest | _] when is_binary(latest) -> latest
          versions when is_map(versions) ->
            versions |> Map.keys() |> Enum.sort(:desc) |> List.first()
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp fetch_from_module_info(name, version) do
    url = "#{@registry_url}/modules/#{name}"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        parse_module_info(name, version, body)

      _ ->
        {:error, :not_found}
    end
  end

  defp parse_rockspec(name, version, content) do
    # Parse Lua rockspec format (subset of Lua table syntax)
    # Extract: description, homepage, license, dependencies
    description = extract_rockspec_field(content, "description")
    homepage = extract_rockspec_field(content, "homepage")
    license = extract_rockspec_field(content, "license")
    deps = parse_rockspec_dependencies(content)

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :luarocks,
      registry_url: "#{@registry_url}/modules/#{name}",
      tarball_url: compute_tarball_url(name, version),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: nil,
        authors: [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :lua,
        raw_manifest: content
      },
      attestations: [],
      resolved_deps: []
    }
    |> then(&{:ok, &1})
  end

  defp parse_module_info(name, version, info) do
    description = Map.get(info, "description") || Map.get(info, "summary")
    homepage = Map.get(info, "homepage")
    license = Map.get(info, "license")

    # Dependencies may be in version-specific data
    deps = extract_dependencies_from_info(info, version)

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :luarocks,
      registry_url: "#{@registry_url}/modules/#{name}",
      tarball_url: compute_tarball_url(name, version),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: license,
        homepage: homepage,
        repository: Map.get(info, "repository"),
        authors: [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :lua,
        raw_manifest: info
      },
      attestations: [],
      resolved_deps: []
    }
    |> then(&{:ok, &1})
  end

  defp extract_rockspec_field(content, field) do
    # Simple regex-based extraction for string fields
    # Format: field = "value" or field = [[value]]
    regex_quoted = ~r/#{field}\s*=\s*"([^"]*)"/
    regex_multiline = ~r/#{field}\s*=\s*\[\[([^\]]*)\]\]/

    cond do
      match = Regex.run(regex_quoted, content) ->
        Enum.at(match, 1)

      match = Regex.run(regex_multiline, content) ->
        Enum.at(match, 1) |> String.trim()

      true ->
        nil
    end
  end

  defp parse_rockspec_dependencies(content) do
    # Extract dependencies table from rockspec
    # Format: dependencies = { "lua >= 5.1", "lpeg ~> 1.0" }
    regex = ~r/dependencies\s*=\s*\{([^\}]*)\}/s

    case Regex.run(regex, content) do
      [_, deps_content] ->
        deps_content
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.trim(&1, "\""))
        |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "lua ")))
        |> Enum.map(&parse_dependency_spec/1)
        |> Enum.into(%{})

      _ ->
        %{}
    end
  end

  defp parse_dependency_spec(spec) do
    # Parse dependency specs like "lpeg ~> 1.0" or "penlight >= 1.3.2"
    case String.split(spec, ~r/\s+/, parts: 2) do
      [name] ->
        {name, "*"}

      [name, version_spec] ->
        {name, version_spec}
    end
  end

  defp extract_dependencies_from_info(info, version) do
    # Try to extract from version-specific data
    case info do
      %{"versions" => versions} when is_map(versions) ->
        case Map.get(versions, version) do
          %{"dependencies" => deps} when is_list(deps) ->
            deps
            |> Enum.map(&parse_dependency_spec/1)
            |> Enum.into(%{})

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp compute_tarball_url(name, version) do
    # LuaRocks tarball format (may vary by package)
    "#{@registry_url}/manifests/#{name}/#{name}-#{version}.src.rock"
  end

  @doc """
  Search for LuaRocks packages.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    url = "#{@registry_url}/search?q=#{URI.encode(query)}&format=json"
    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_list(body) ->
        results = body
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, results}

      {:ok, %{"results" => results}} when is_list(results) ->
        parsed = results
          |> Enum.take(limit)
          |> Enum.map(&parse_search_result/1)

        {:ok, parsed}

      _ ->
        {:ok, []}
    end
  end

  defp parse_search_result(result) when is_map(result) do
    %{
      name: Map.get(result, "name") || Map.get(result, "module_name"),
      version: Map.get(result, "version") || Map.get(result, "latest_version"),
      description: Map.get(result, "description") || Map.get(result, "summary") || "",
      downloads: Map.get(result, "downloads") || 0
    }
  end

  defp parse_search_result(_), do: nil

  @doc """
  Check if a LuaRocks package exists.
  """
  def exists?(name) do
    url = "#{@registry_url}/modules/#{name}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a LuaRocks package.
  """
  def versions(name) do
    url = "#{@registry_url}/modules/#{name}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_map(versions) ->
        version_list = versions
          |> Map.keys()
          |> Enum.sort(:desc)

        {:ok, version_list}

      {:ok, %{"versions" => versions}} when is_list(versions) ->
        {:ok, Enum.sort(versions, :desc)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Get tarball URL for a specific version.
  """
  def tarball_url(name, version) do
    {:ok, compute_tarball_url(name, version)}
  end
end
