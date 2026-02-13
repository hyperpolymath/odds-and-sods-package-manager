# SPDX-License-Identifier: PMPL-1.0-or-later
defmodule Opsm.Registries.Elpa do
  @moduledoc """
  GNU ELPA (Emacs Lisp Package Archive) registry adapter.
  https://elpa.gnu.org/packages/
  Uses the GNU ELPA archive-contents endpoint for Emacs package metadata.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @packages_url "https://elpa.gnu.org/packages"

  @doc """
  Fetch Emacs package metadata from GNU ELPA.
  Uses the per-package JSON endpoint for structured metadata.
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@packages_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        target_version = if version == "latest" do
          extract_latest_version(body)
        else
          version
        end

        deps = extract_deps(body)
        {:ok, parse_package(name, body, target_version, deps)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, %{status: status}} ->
        {:error, "GNU ELPA returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for packages on GNU ELPA.
  GNU ELPA has no search API; fetches the package list and filters client-side.
  """
  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    _url = "#{@packages_url}/"

    case VerifiedHttp.get_json("#{@packages_url}/archive-contents.json", receive_timeout: 10_000) do
      {:ok, packages} when is_list(packages) ->
        downcased = String.downcase(query)

        results = packages
        |> Enum.filter(fn pkg ->
          name = pkg["name"] || ""
          desc = pkg["description"] || pkg["summary"] || ""
          String.contains?(String.downcase(name), downcased) ||
            String.contains?(String.downcase(desc), downcased)
        end)
        |> Enum.take(limit)
        |> Enum.map(fn pkg ->
          %{
            name: pkg["name"],
            version: pkg["version"],
            description: pkg["description"] || pkg["summary"] || "",
            downloads: 0
          }
        end)

        {:ok, results}

      {:ok, packages} when is_map(packages) ->
        downcased = String.downcase(query)

        results = packages
        |> Enum.filter(fn {name, _data} ->
          String.contains?(String.downcase(name), downcased)
        end)
        |> Enum.take(limit)
        |> Enum.map(fn {name, data} ->
          ver = case data do
            %{"version" => v} -> v
            _ -> nil
          end
          %{
            name: name,
            version: ver,
            description: Map.get(data, "description", ""),
            downloads: 0
          }
        end)

        {:ok, results}

      {:error, %{status: status}} ->
        {:error, "GNU ELPA search returned status #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if a package exists on GNU ELPA.
  """
  def exists?(name) do
    url = "#{@packages_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of a GNU ELPA package.
  GNU ELPA typically provides only the latest version per package.
  """
  def versions(name) do
    url = "#{@packages_url}/#{URI.encode(name)}.json"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        ver = extract_latest_version(body)
        if ver, do: {:ok, [ver]}, else: {:ok, []}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get tarball URL for a GNU ELPA package.
  """
  def tarball_url(name, version) do
    {:ok, "#{@packages_url}/#{name}-#{version}.tar"}
  end

  # Parsers

  defp extract_latest_version(body) do
    case body do
      %{"version" => ver} when is_binary(ver) -> ver
      %{"version" => ver} when is_list(ver) -> Enum.join(ver, ".")
      %{"latest" => ver} when is_binary(ver) -> ver
      _ -> nil
    end
  end

  defp extract_deps(body) do
    case Map.get(body, "dependencies") || Map.get(body, "requires") do
      deps when is_map(deps) ->
        Enum.reduce(deps, %{}, fn {dep_name, constraint}, acc ->
          ver = case constraint do
            c when is_binary(c) -> c
            c when is_list(c) -> ">= #{Enum.join(c, ".")}"
            _ -> ">= 0.0.0"
          end
          Map.put(acc, dep_name, ver)
        end)

      deps when is_list(deps) ->
        Enum.reduce(deps, %{}, fn dep, acc ->
          case dep do
            [dep_name | ver_parts] ->
              Map.put(acc, to_string(dep_name), ">= #{Enum.join(ver_parts, ".")}")
            dep_name when is_binary(dep_name) ->
              Map.put(acc, dep_name, ">= 0.0.0")
            _ ->
              acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp parse_package(name, body, version, deps) do
    description = Map.get(body, "description") || Map.get(body, "summary", "")

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :elpa,
      registry_url: "#{@packages_url}/#{name}.html",
      tarball_url: "#{@packages_url}/#{name}-#{version}.tar",
      checksum: nil,
      checksum_algo: nil,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: description,
        license: Map.get(body, "license"),
        homepage: "#{@packages_url}/#{name}.html",
        repository: Map.get(body, "url"),
        authors: extract_authors(Map.get(body, "maintainer") || Map.get(body, "author")),
        keywords: Map.get(body, "keywords") || [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :elpa,
        raw_manifest: body
      },
      attestations: [],
      resolved_deps: []
    }
  end

  defp extract_authors(nil), do: []
  defp extract_authors(author) when is_binary(author), do: [author]
  defp extract_authors(authors) when is_list(authors), do: authors
  defp extract_authors(_), do: []
end
