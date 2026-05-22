# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Registries.Opam do
  @moduledoc """
  OPAM (OCaml Package Manager) registry API client.
  https://opam.ocaml.org/
  Uses the OPAM repository structure and package metadata format.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @base_url "https://opam.ocaml.org"

  @doc """
  Fetch package metadata from the OPAM registry.
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
        # Fetch OPAM file for package metadata
        url = "#{@base_url}/packages/#{name}/#{name}.#{ver}/opam"
        case VerifiedHttp.get(url, receive_timeout: 10_000) do
          {:ok, %{body: body}} when is_binary(body) ->
            deps = parse_opam_deps(body)
            {:ok, parse_package(name, ver, body, deps)}

          {:ok, body} when is_binary(body) ->
            deps = parse_opam_deps(body)
            {:ok, parse_package(name, ver, body, deps)}

          {:error, :not_found} ->
            {:error, :not_found}

          {:error, %{status: 404}} ->
            {:error, :not_found}

          {:error, %{status: status}} ->
            {:error, "OPAM registry returned status #{status}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp fetch_latest_version(name) do
    case versions_internal(name) do
      {:ok, [latest | _]} -> latest
      _ -> nil
    end
  end

  defp parse_opam_deps(content) do
    # Parse depends field from OPAM file
    # Format: depends: [ "package" {>= "version"} "package2" {= "version"} ]
    # Also supports multi-line format with parentheses
    content
    |> String.split("\n")
    |> Enum.reduce({false, %{}}, fn line, {in_depends, deps} ->
      trimmed = String.trim(line)
      cond do
        String.starts_with?(trimmed, "depends:") ->
          # Start of depends block
          rest = String.replace_prefix(trimmed, "depends:", "") |> String.trim()
          if String.starts_with?(rest, "[") do
            # Parse inline dependencies
            parse_depends_line(rest, deps)
          else
            {true, deps}
          end

        String.starts_with?(trimmed, "]") and in_depends ->
          {false, deps}

        in_depends and trimmed != "" and not String.starts_with?(trimmed, "#") ->
          # Parse dependency line
          parse_depends_line(trimmed, deps)

        true ->
          {in_depends, deps}
      end
    end)
    |> elem(1)
  end

  defp parse_depends_line(line, deps) do
    # Parse dependencies from a line
    # Format: "package" {>= "version"} or "package"
    line
    |> String.replace(~r/[\[\]]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce({deps, nil}, fn token, {acc_deps, current_pkg} ->
      cond do
        String.starts_with?(token, "\"") and String.ends_with?(token, "\"") ->
          # Package name
          pkg = String.trim(token, "\"")
          # Skip ocaml base packages
          if pkg in ["ocaml", "base-unix", "base-threads", "ocamlfind"] do
            {acc_deps, nil}
          else
            {acc_deps, pkg}
          end

        String.starts_with?(token, "{") and current_pkg != nil ->
          # Version constraint
          constraint = String.replace(token, ~r/[{}]/, "")
          {Map.put(acc_deps, current_pkg, constraint), nil}

        true ->
          {acc_deps, current_pkg}
      end
    end)
    |> elem(0)
    |> then(&{false, &1})
  end

  @doc """
  Search for OPAM packages.
  OPAM has no official search API - check if package exists.
  """
  def search(query, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 20)

    # Check if the query is a direct package name
    case VerifiedHttp.get("#{@base_url}/packages/#{query}/", receive_timeout: 10_000) do
      {:ok, _} ->
        case versions_internal(query) do
          {:ok, [latest | _]} ->
            {:ok, [%{name: query, version: latest, description: "OCaml package", downloads: 0}]}
          _ ->
            {:ok, []}
        end

      _ ->
        {:ok, []}
    end
  end

  @doc """
  Check if an OPAM package exists.
  """
  def exists?(name) do
    url = "#{@base_url}/packages/#{name}/"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  @doc """
  Get all versions of an OPAM package.
  Fetches version list from package index.
  """
  def versions(name) do
    versions_internal(name)
  end

  defp versions_internal(name) do
    # OPAM package index at /packages/{name}/ lists versions
    # We need to parse HTML or use the packages index
    # Fallback: try to fetch versions from package list endpoint
    url = "#{@base_url}/packages/#{name}/"

    case VerifiedHttp.get(url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        versions = parse_versions_from_html(body, name)
        if versions == [] do
          {:error, :not_found}
        else
          {:ok, Enum.reverse(versions)}
        end

      {:ok, body} when is_binary(body) ->
        versions = parse_versions_from_html(body, name)
        if versions == [] do
          {:error, :not_found}
        else
          {:ok, Enum.reverse(versions)}
        end

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_versions_from_html(html, name) do
    # Parse version links from HTML
    # Format: <a href="/packages/{name}/{name}.{version}/">
    html
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      Regex.scan(~r{/packages/#{Regex.escape(name)}/#{Regex.escape(name)}\.([\w\.\-\+]+)/}, line)
      |> Enum.map(fn [_, version] -> version end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Get tarball URL for a specific version.

  OPAM packages declare their source archive URL in the `url { src: "..." }`
  field of the opam file. This function fetches the opam file and extracts
  that URL. If the `url.src` field is not found (e.g., virtual packages or
  packages with only git sources), returns the opam file URL as a fallback.
  """
  def tarball_url(name, version) do
    opam_url = "#{@base_url}/packages/#{name}/#{name}.#{version}/opam"

    case VerifiedHttp.get(opam_url, receive_timeout: 10_000) do
      {:ok, %{body: body}} when is_binary(body) ->
        case extract_archive_url(body) do
          nil -> {:ok, opam_url}
          archive_url -> {:ok, archive_url}
        end

      {:ok, body} when is_binary(body) ->
        case extract_archive_url(body) do
          nil -> {:ok, opam_url}
          archive_url -> {:ok, archive_url}
        end

      _ ->
        {:ok, opam_url}
    end
  end

  # Extract the archive URL from the opam file's url { src: "..." } block.
  # The format is:
  #   url {
  #     src: "https://github.com/.../archive/v1.0.0.tar.gz"
  #     checksum: "sha256=..."
  #   }
  defp extract_archive_url(opam_content) do
    opam_content
    |> String.split("\n")
    |> Enum.reduce_while(nil, fn line, _acc ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "src:") do
        url = trimmed
          |> String.replace_prefix("src:", "")
          |> String.trim()
          |> String.trim("\"")
        {:halt, url}
      else
        {:cont, nil}
      end
    end)
  end

  # Parsers

  defp parse_package(name, version, opam_content, deps) do
    # Extract metadata from OPAM file
    license = extract_field(opam_content, "license")
    homepage = extract_field(opam_content, "homepage")
    synopsis = extract_field(opam_content, "synopsis")
    authors = extract_authors(opam_content)
    archive_url = extract_archive_url(opam_content)
    {checksum, checksum_algo} = extract_checksum(opam_content)

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :opam,
      registry_url: "#{@base_url}/packages/#{name}/#{name}.#{version}/",
      tarball_url: archive_url,
      checksum: checksum,
      checksum_algo: checksum_algo,
      manifest: %ManifestFormat{
        name: name,
        version: version,
        description: synopsis,
        license: license,
        homepage: homepage,
        repository: nil,
        authors: authors,
        keywords: [],
        dependencies: deps,
        dev_dependencies: %{},
        source_forth: :opam,
        raw_manifest: opam_content
      },
      attestations: [],
      resolved_deps: []
    }
  end

  # Extract checksum from the opam file's url { checksum: "sha256=..." } block.
  # Returns {hash_value, hash_algorithm} or {nil, nil}.
  defp extract_checksum(opam_content) do
    opam_content
    |> String.split("\n")
    |> Enum.reduce_while({nil, nil}, fn line, _acc ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "checksum:") do
        raw = trimmed
          |> String.replace_prefix("checksum:", "")
          |> String.trim()
          |> String.trim("\"")

        result = case String.split(raw, "=", parts: 2) do
          ["sha256", value] -> {value, :sha256}
          ["sha512", value] -> {value, :sha512}
          ["md5", value] -> {value, :md5}
          _ -> {nil, nil}
        end

        {:halt, result}
      else
        {:cont, {nil, nil}}
      end
    end)
  end

  defp extract_field(content, field_name) do
    content
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      if String.starts_with?(String.trim(line), "#{field_name}:") do
        String.replace_prefix(line, "#{field_name}:", "")
        |> String.trim()
        |> String.trim("\"")
      end
    end)
  end

  defp extract_authors(content) do
    # Authors can be multi-line: authors: [ "Name <email>" "Name2" ]
    content
    |> String.split("\n")
    |> Enum.reduce({false, []}, fn line, {in_authors, authors} ->
      trimmed = String.trim(line)
      cond do
        String.starts_with?(trimmed, "authors:") ->
          rest = String.replace_prefix(trimmed, "authors:", "") |> String.trim()
          if String.starts_with?(rest, "[") and String.contains?(rest, "]") do
            # Single line authors
            parsed = parse_authors_line(rest)
            {false, authors ++ parsed}
          else
            {true, authors}
          end

        String.starts_with?(trimmed, "]") and in_authors ->
          {false, authors}

        in_authors and trimmed != "" ->
          parsed = parse_authors_line(trimmed)
          {true, authors ++ parsed}

        true ->
          {in_authors, authors}
      end
    end)
    |> elem(1)
  end

  defp parse_authors_line(line) do
    line
    |> String.replace(~r/[\[\]]/, " ")
    |> String.split("\"", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
