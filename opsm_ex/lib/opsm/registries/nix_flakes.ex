# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.NixFlakes do
  @moduledoc """
  Nix Flakes registry adapter.
  https://flakestry.dev/
  Queries the Flakestry API for discoverable Nix flakes, which provide
  reproducible, composable Nix package definitions with lock files.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://flakestry.dev/api"

  @doc """
  Fetch flake metadata from Flakestry.
  Name should be in "owner/repo" format (e.g., "NixOS/nixpkgs").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/flake/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        releases = body["releases"] || body["versions"] || []

        ver = if version == "latest" do
          case releases do
            [latest | _] -> latest["version"] || latest["ref"] || "0.0.0"
            _ -> body["version"] || "0.0.0"
          end
        else
          version
        end

        {:ok, parse_flake(name, body, ver, releases)}

      {:error, :not_found} -> {:error, :not_found}
      {:error, %{status: 404}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_flake(name, body, version, releases) do
    outputs = body["outputs"] || %{}
    output_names = Map.keys(outputs)

    # Extract flake inputs as dependencies
    inputs = body["inputs"] || %{}
    deps = inputs
           |> Enum.map(fn {k, v} ->
             ref = if is_map(v), do: v["url"] || v["ref"] || "*", else: "*"
             {k, ref}
           end)
           |> Map.new()

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: body["description"],
      license: body["license"],
      homepage: body["homepage"] || body["url"],
      repository: body["source"] || "https://github.com/#{name}",
      keywords: output_names,
      dependencies: deps,
      source_forth: :nix_flakes,
      raw_manifest: body
    }

    tarball = case releases do
      [latest | _] -> latest["tarball_url"] || latest["archive_url"]
      _ -> nil
    end

    checksum = case releases do
      [latest | _] -> latest["hash"] || latest["narHash"]
      _ -> nil
    end

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :nix_flakes,
      registry_url: "https://flakestry.dev",
      manifest: manifest,
      tarball_url: tarball,
      checksum: checksum,
      checksum_algo: if(checksum, do: :sha256),
      attestations: [],
      resolved_deps: []
    }
  end

  @doc """
  Search for flakes on Flakestry.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/search?q=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, items} when is_list(items) ->
        results = items
        |> Enum.take(20)
        |> Enum.map(fn flake ->
          %{
            name: flake["name"] || flake["full_name"],
            version: flake["version"],
            description: flake["description"]
          }
        end)
        {:ok, results}

      {:ok, body} ->
        results = (body["results"] || body["flakes"] || [])
        |> Enum.take(20)
        |> Enum.map(fn flake ->
          %{
            name: flake["name"] || flake["full_name"],
            version: flake["version"] || flake["ref"],
            description: flake["description"]
          }
        end)
        {:ok, results}

      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Check if a flake exists on Flakestry.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions (releases/refs) for a flake.
  """
  def versions(name) do
    url = "#{@api_url}/flake/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        releases = body["releases"] || body["versions"] || []
        vers = releases
               |> Enum.map(fn r -> r["version"] || r["ref"] end)
               |> Enum.reject(&is_nil/1)
        {:ok, vers}

      {:error, _} = err -> err
    end
  end
end
