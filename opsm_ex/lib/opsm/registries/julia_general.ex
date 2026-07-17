# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.JuliaGeneral do
  @moduledoc """
  Julia General registry adapter.
  https://juliahub.com
  Uses JuliaHub API for package metadata.
  """

  alias Opsm.Types.{ResolvedPackage, ManifestFormat}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://juliahub.com/app/packages"
  @web_url "https://juliahub.com/ui/Packages"

  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/info?name=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        ver =
          if version == "latest" do
            body["version"] || "0.0.0"
          else
            version
          end

        deps = parse_deps(body["deps"] || [])

        {:ok,
         %ResolvedPackage{
           package: name,
           version: ver,
           forth: :julia,
           registry_url: "#{@web_url}/#{name}",
           tarball_url: nil,
           checksum: nil,
           checksum_algo: nil,
           manifest: %ManifestFormat{
             name: name,
             version: ver,
             description: body["description"],
             license: body["license"],
             homepage: body["homepage"] || "#{@web_url}/#{name}",
             repository: body["repo"],
             authors: body["authors"] || [],
             keywords: [],
             dependencies: deps,
             dev_dependencies: %{},
             source_forth: :julia,
             raw_manifest: body
           },
           attestations: [],
           resolved_deps: []
         }}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    url = "#{@api_url}/search?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, results} when is_list(results) ->
        packages =
          results
          |> Enum.take(limit)
          |> Enum.map(fn r ->
            %{name: r["name"], version: r["version"], description: r["description"], downloads: 0}
          end)

        {:ok, packages}

      _ ->
        {:ok, []}
    end
  end

  def exists?(name) do
    url = "#{@api_url}/info?name=#{URI.encode(name)}"

    case VerifiedHttp.get(url, receive_timeout: 5_000) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def versions(name) do
    url = "#{@api_url}/info?name=#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, %{"versions" => versions}} when is_list(versions) ->
        vers = Enum.map(versions, fn v -> v["version"] || v end) |> Enum.reject(&is_nil/1)
        {:ok, vers}

      {:ok, %{"version" => ver}} when is_binary(ver) ->
        {:ok, [ver]}

      _ ->
        {:error, :not_found}
    end
  end

  def tarball_url(_name, _version), do: {:ok, nil}

  defp parse_deps(deps) when is_list(deps) do
    Enum.into(deps, %{}, fn
      dep when is_map(dep) -> {dep["name"] || "", dep["compat"] || "*"}
      dep when is_binary(dep) -> {dep, "*"}
      _ -> {"", "*"}
    end)
    |> Map.delete("")
  end

  defp parse_deps(_), do: %{}
end
