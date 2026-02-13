# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.VimPlugins do
  @moduledoc """
  Vim/Neovim Plugin Registry API client (Vim Awesome).
  https://vimawesome.com/api/
  Provides access to the Vim Awesome directory of Vim and Neovim
  plugins. Plugins are typically sourced from GitHub or vim.org.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://vimawesome.com/api"

  @doc """
  Fetch plugin metadata from Vim Awesome.
  The `name` is the plugin slug (e.g., "nerdtree", "vim-fugitive").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/plugins/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        resolved_version = if version == "latest" do
          extract_version(body)
        else
          version
        end
        {:ok, parse_plugin(body, resolved_version)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "Vim Awesome API returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for Vim/Neovim plugins on Vim Awesome.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/plugins?query=#{URI.encode_www_form(query)}&page=1"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"plugins" => plugins}} when is_list(plugins) ->
        results =
          plugins
          |> Enum.take(limit)
          |> Enum.map(fn plugin ->
            %{
              name: plugin["slug"] || plugin["name"],
              version: extract_version(plugin),
              description: plugin["short_desc"] || plugin["description"]
            }
          end)

        {:ok, results}

      {:ok, plugins} when is_list(plugins) ->
        results =
          plugins
          |> Enum.take(limit)
          |> Enum.map(fn plugin ->
            %{
              name: plugin["slug"] || plugin["name"],
              version: extract_version(plugin),
              description: plugin["short_desc"] || plugin["description"]
            }
          end)

        {:ok, results}

      {:ok, _} ->
        {:ok, []}

      {:error, %{status: status}} ->
        {:error, "Vim Awesome search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a Vim plugin exists on Vim Awesome.
  """
  def exists?(name) do
    url = "#{@api_url}/plugins/#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get available versions of a Vim plugin.
  Vim Awesome does not track per-plugin versions natively; instead
  we return GitHub tags if the source repo is on GitHub, or the
  current version from the plugin metadata.
  """
  def versions(name) do
    url = "#{@api_url}/plugins/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        case extract_github_tags(body) do
          {:ok, tags} when tags != [] ->
            {:ok, tags}

          _ ->
            case extract_version(body) do
              nil -> {:ok, []}
              ver -> {:ok, [ver]}
            end
        end

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

  defp parse_plugin(json, version) do
    slug = json["slug"] || json["name"]
    github_url = extract_github_url(json)

    %ResolvedPackage{
      package: slug,
      version: version,
      forth: :vim_plugins,
      registry_url: "https://vimawesome.com/plugin/#{slug}",
      tarball_url: build_tarball_url(github_url, version),
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: slug,
        version: version,
        description: json["short_desc"] || json["description"],
        license: nil,
        homepage: github_url || "https://vimawesome.com/plugin/#{slug}",
        repository: github_url,
        authors: extract_authors(json),
        keywords: extract_tags(json),
        dependencies: %{},
        dev_dependencies: %{},
        source_forth: :vim_plugins,
        raw_manifest: json
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_version(json) do
    case json do
      %{"version" => ver} when is_binary(ver) and ver != "" -> ver
      %{"github_stars" => _} -> json["updated_at"]
      _ -> nil
    end
  end

  defp extract_github_url(json) do
    case json do
      %{"github_url" => url} when is_binary(url) and url != "" ->
        url

      %{"github_owner" => owner, "github_repo_name" => repo}
      when is_binary(owner) and is_binary(repo) ->
        "https://github.com/#{owner}/#{repo}"

      _ ->
        nil
    end
  end

  defp extract_authors(json) do
    case json do
      %{"author" => author} when is_binary(author) and author != "" ->
        [author]

      %{"github_owner" => owner} when is_binary(owner) and owner != "" ->
        [owner]

      _ ->
        []
    end
  end

  defp extract_tags(json) do
    case json do
      %{"tags" => tags} when is_list(tags) ->
        Enum.map(tags, fn
          tag when is_binary(tag) -> tag
          %{"name" => name} -> name
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      %{"category" => cat} when is_binary(cat) ->
        [cat]

      _ ->
        []
    end
  end

  defp build_tarball_url(nil, _version), do: nil

  defp build_tarball_url(github_url, version) do
    clean = String.trim_trailing(github_url, "/")

    case version do
      nil -> "#{clean}/archive/refs/heads/master.tar.gz"
      ver -> "#{clean}/archive/refs/tags/#{ver}.tar.gz"
    end
  end

  defp extract_github_tags(json) do
    github_url = extract_github_url(json)

    case github_url do
      nil ->
        {:ok, []}

      url ->
        # Derive the GitHub API URL for tags
        case Regex.run(~r{github\.com/([^/]+)/([^/]+)}, url) do
          [_, owner, repo] ->
            tags_url = "https://api.github.com/repos/#{owner}/#{repo}/tags?per_page=30"

            case VerifiedHttp.get_json(tags_url, receive_timeout: 10_000) do
              {:ok, tags} when is_list(tags) ->
                version_list =
                  Enum.map(tags, fn tag -> tag["name"] end)
                  |> Enum.reject(&is_nil/1)

                {:ok, version_list}

              _ ->
                {:ok, []}
            end

          _ ->
            {:ok, []}
        end
    end
  end
end
