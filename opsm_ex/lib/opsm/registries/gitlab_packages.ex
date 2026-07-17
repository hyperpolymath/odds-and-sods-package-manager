# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.GitlabPackages do
  @moduledoc """
  GitLab Packages registry adapter.
  https://gitlab.com/api/v4
  Queries the GitLab Packages API for package metadata across supported types:
  npm, PyPI, Maven, NuGet, Conan, Composer, Helm, and generic packages.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://gitlab.com/api/v4"

  @doc """
  Fetch package metadata from GitLab Packages.
  Name format: "project_id/package_name" or "group/project/package_name".
  """
  def fetch_package(name, version \\ "latest") do
    {project_id, package_name} = parse_package_ref(name)

    url =
      "#{@api_url}/projects/#{URI.encode(project_id, &URI.char_unreserved?/1)}/packages?package_name=#{URI.encode_www_form(package_name)}&sort=desc"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, packages} when is_list(packages) and length(packages) > 0 ->
        target = find_target_package(packages, version)

        case target do
          nil ->
            {:error, :not_found}

          pkg_data ->
            ver = pkg_data["version"] || version
            {:ok, parse_gitlab_package(project_id, package_name, pkg_data, ver)}
        end

      {:ok, _} ->
        {:error, :not_found}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "GitLab Packages returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_target_package(packages, "latest") do
    List.first(packages)
  end

  defp find_target_package(packages, target_version) do
    Enum.find(packages, List.first(packages), fn pkg ->
      pkg["version"] == target_version
    end)
  end

  @doc """
  Search for packages on GitLab.
  Searches across public projects that have published packages.
  """
  def search(query, opts \\ []) do
    per_page = Keyword.get(opts, :limit, 20)

    url =
      "#{@api_url}/projects?search=#{URI.encode_www_form(query)}&with_packages=true&per_page=#{per_page}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, projects} when is_list(projects) ->
        results =
          Enum.map(projects, fn project ->
            %{
              name: project["path_with_namespace"],
              version: nil,
              description: project["description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on GitLab Packages.
  """
  def exists?(name) do
    {project_id, package_name} = parse_package_ref(name)

    url =
      "#{@api_url}/projects/#{URI.encode(project_id, &URI.char_unreserved?/1)}/packages?package_name=#{URI.encode_www_form(package_name)}&per_page=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, packages} when is_list(packages) and length(packages) > 0 -> true
      {:ok, _} -> false
      {:error, _} -> false
    end
  end

  @doc """
  Get all available versions for a package on GitLab Packages.
  Returns version strings, newest first.
  """
  def versions(name) do
    {project_id, package_name} = parse_package_ref(name)

    url =
      "#{@api_url}/projects/#{URI.encode(project_id, &URI.char_unreserved?/1)}/packages?package_name=#{URI.encode_www_form(package_name)}&sort=desc&per_page=100"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, packages} when is_list(packages) ->
        version_list =
          packages
          |> Enum.map(fn pkg -> pkg["version"] end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

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

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp parse_package_ref(name) do
    # Supports "project_id/package_name" or "group/project/package_name"
    parts = String.split(name, "/")

    case parts do
      [project_id, package_name] ->
        {project_id, package_name}

      [group, project, package_name] ->
        {"#{group}%2F#{project}", package_name}

      [package_name] ->
        {"_", package_name}

      _ ->
        # Join all but last as project path, last is package name
        {init, [pkg]} = Enum.split(parts, -1)
        project_path = Enum.join(init, "%2F")
        {project_path, pkg}
    end
  end

  defp parse_gitlab_package(project_id, package_name, pkg_data, version) do
    package_type = pkg_data["package_type"] || "generic"

    manifest = %ManifestFormat{
      name: package_name,
      version: version,
      description: "GitLab #{package_type} package: #{package_name}",
      license: nil,
      homepage: pkg_data["_links"]["web_path"],
      repository: nil,
      authors: [],
      keywords: extract_tags(pkg_data),
      dependencies: %{},
      dev_dependencies: %{},
      source_forth: :gitlab_packages,
      raw_manifest: pkg_data
    }

    registry_url = "https://gitlab.com/#{URI.decode(project_id)}/-/packages"

    %ResolvedPackage{
      package: package_name,
      version: version,
      forth: :gitlab_packages,
      registry_url: registry_url,
      tarball_url: nil,
      checksum: nil,
      checksum_algo: :sha256,
      manifest: manifest,
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_tags(pkg_data) do
    (pkg_data["tags"] || [])
    |> Enum.map(fn
      tag when is_binary(tag) -> tag
      %{"name" => name} -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end
end
