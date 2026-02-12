# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Terraform do
  @moduledoc """
  HashiCorp Terraform Registry API client.
  https://registry.terraform.io/
  Supports both modules and providers from the official Terraform Registry.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @registry_url "https://registry.terraform.io/v1"

  @doc """
  Fetch module or provider metadata from the Terraform Registry.
  Supports both modules (namespace/name/provider) and providers (namespace/name).
  """
  def fetch_package(name, version \\ "latest") do
    case parse_package_name(name) do
      {:module, namespace, pkg_name, provider} ->
        fetch_module(namespace, pkg_name, provider, version)

      {:provider, namespace, pkg_name} ->
        fetch_provider(namespace, pkg_name, version)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_module(namespace, name, provider, version) do
    target_version = if version == "latest" do
      fetch_latest_module_version(namespace, name, provider)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        url = "#{@registry_url}/modules/#{namespace}/#{name}/#{provider}/#{ver}"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, parse_module(namespace, name, provider, body, ver)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Terraform Registry returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_provider(namespace, name, version) do
    target_version = if version == "latest" do
      fetch_latest_provider_version(namespace, name)
    else
      version
    end

    case target_version do
      nil ->
        {:error, :not_found}

      ver ->
        url = "#{@registry_url}/providers/#{namespace}/#{name}/#{ver}"
        case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
          {:ok, body} ->
            {:ok, parse_provider(namespace, name, body, ver)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "Terraform Registry returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_module_version(namespace, name, provider) do
    case versions_module_internal(namespace, name, provider) do
      {:ok, [latest | _]} -> latest
      _ -> nil
    end
  end

  defp fetch_latest_provider_version(namespace, name) do
    case versions_provider_internal(namespace, name) do
      {:ok, [latest | _]} -> latest
      _ -> nil
    end
  end

  @doc """
  Search for Terraform modules or providers.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    type = Keyword.get(opts, :type, :module)

    endpoint = case type do
      :provider -> "/providers"
      _ -> "/modules"
    end

    url = "#{@registry_url}#{endpoint}?q=#{URI.encode_www_form(query)}&limit=#{limit}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"modules" => modules}} when is_list(modules) ->
        results = Enum.map(modules, &parse_search_module/1)
        {:ok, results}

      {:ok, %{"providers" => providers}} when is_list(providers) ->
        results = Enum.map(providers, &parse_search_provider/1)
        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Terraform module or provider exists.
  """
  def exists?(name) do
    case parse_package_name(name) do
      {:module, namespace, pkg_name, provider} ->
        url = "#{@registry_url}/modules/#{namespace}/#{pkg_name}/#{provider}/versions"
        check_exists(url)

      {:provider, namespace, pkg_name} ->
        url = "#{@registry_url}/providers/#{namespace}/#{pkg_name}/versions"
        check_exists(url)

      {:error, _} ->
        false
    end
  end

  defp check_exists(url) do
    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a Terraform module or provider.
  """
  def versions(name) do
    case parse_package_name(name) do
      {:module, namespace, pkg_name, provider} ->
        versions_module_internal(namespace, pkg_name, provider)

      {:provider, namespace, pkg_name} ->
        versions_provider_internal(namespace, pkg_name)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp versions_module_internal(namespace, name, provider) do
    url = "#{@registry_url}/modules/#{namespace}/#{name}/#{provider}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"modules" => [%{"versions" => versions}]}} when is_list(versions) ->
        version_list = versions
        |> Enum.map(fn %{"version" => v} -> v end)
        |> Enum.reverse()
        {:ok, version_list}

      {:ok, _} ->
        {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp versions_provider_internal(namespace, name) do
    url = "#{@registry_url}/providers/#{namespace}/#{name}/versions"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        version_list = versions
        |> Enum.map(fn %{"version" => v} -> v end)
        |> Enum.reverse()
        {:ok, version_list}

      {:ok, _} ->
        {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get download URL for a specific version.
  For modules, returns the download URL from the API.
  For providers, returns the download metadata endpoint.
  """
  def tarball_url(name, version) do
    case parse_package_name(name) do
      {:module, namespace, pkg_name, provider} ->
        url = "#{@registry_url}/modules/#{namespace}/#{pkg_name}/#{provider}/#{version}/download"
        {:ok, url}

      {:provider, namespace, pkg_name} ->
        # Provider downloads are platform-specific, return the base download endpoint
        url = "#{@registry_url}/providers/#{namespace}/#{pkg_name}/#{version}/download"
        {:ok, url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Parse Terraform package names
  # Modules: "namespace/name/provider" (e.g., "hashicorp/consul/aws")
  # Providers: "namespace/name" (e.g., "hashicorp/aws")
  defp parse_package_name(name) do
    parts = String.split(name, "/")

    case parts do
      [namespace, pkg_name, provider] ->
        {:module, namespace, pkg_name, provider}

      [namespace, pkg_name] ->
        {:provider, namespace, pkg_name}

      _ ->
        {:error, "Invalid package name format. Expected 'namespace/name' or 'namespace/name/provider'"}
    end
  end

  # Parsers

  defp parse_module(namespace, name, provider, data, version) do
    full_name = "#{namespace}/#{name}/#{provider}"
    deps = extract_module_dependencies(data)

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :terraform,
      registry_url: "https://registry.terraform.io/modules/#{full_name}",
      tarball_url: "#{@registry_url}/modules/#{full_name}/#{version}/download",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: full_name,
        version: version,
        description: Map.get(data, "description"),
        license: nil,
        homepage: Map.get(data, "source"),
        repository: Map.get(data, "source"),
        authors: [],
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :terraform,
        raw_manifest: data
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp parse_provider(namespace, name, data, version) do
    full_name = "#{namespace}/#{name}"

    %ResolvedPackage{
      package: full_name,
      version: version,
      forth: :terraform,
      registry_url: "https://registry.terraform.io/providers/#{full_name}",
      tarball_url: "#{@registry_url}/providers/#{full_name}/#{version}/download",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: full_name,
        version: version,
        description: Map.get(data, "description"),
        license: nil,
        homepage: Map.get(data, "source"),
        repository: Map.get(data, "source"),
        authors: [],
        keywords: [],
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :terraform,
        raw_manifest: data
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_module_dependencies(data) do
    # Terraform modules can have dependencies on other modules or providers
    # These are typically in the "dependencies" or "providers" fields
    providers = data
    |> Map.get("providers", [])
    |> Enum.reduce(%{}, fn provider, acc ->
      case provider do
        %{"name" => name, "version" => version} ->
          Map.put(acc, name, version)
        %{"name" => name} ->
          Map.put(acc, name, "*")
        _ ->
          acc
      end
    end)

    dependencies = data
    |> Map.get("dependencies", [])
    |> Enum.reduce(providers, fn dep, acc ->
      case dep do
        %{"name" => name, "version" => version} ->
          Map.put(acc, name, version)
        %{"name" => name} ->
          Map.put(acc, name, "*")
        _ ->
          acc
      end
    end)

    dependencies
  end

  defp parse_search_module(result) do
    %{
      name: "#{result["namespace"]}/#{result["name"]}/#{result["provider"]}",
      version: result["version"],
      description: result["description"] || "Terraform module",
      downloads: result["downloads"] || 0
    }
  end

  defp parse_search_provider(result) do
    %{
      name: "#{result["namespace"]}/#{result["name"]}",
      version: result["version"],
      description: result["description"] || "Terraform provider",
      downloads: result["downloads"] || 0
    }
  end
end
