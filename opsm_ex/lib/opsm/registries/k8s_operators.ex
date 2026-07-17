# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Registries.K8sOperators do
  @moduledoc """
  Kubernetes Operators registry adapter (OperatorHub.io).
  https://operatorhub.io/api
  Queries the OperatorHub.io API for Kubernetes operators published
  via the Operator Lifecycle Manager (OLM) framework.
  """

  alias Opsm.Types.{ManifestFormat, ResolvedPackage}
  alias Opsm.Verified.Http, as: VerifiedHttp

  @api_url "https://operatorhub.io/api"

  @doc """
  Fetch operator metadata from OperatorHub.io.
  Name should be the operator package name (e.g., "prometheus").
  """
  def fetch_package(name, version \\ "latest") do
    url = "#{@api_url}/operator/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        operator = body["operator"] || body
        csv = operator["csv"] || %{}
        metadata = csv["metadata"] || %{}
        spec = csv["spec"] || %{}
        _annotations = metadata["annotations"] || %{}

        ver =
          if version == "latest" do
            spec["version"] || metadata["name"] |> extract_version_from_name() || "0.0.0"
          else
            version
          end

        {:ok, parse_operator(name, operator, csv, ver)}

      {:error, :not_found} ->
        {:error, :not_found}

      {:error, %{status: 404}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_version_from_name(nil), do: nil

  defp extract_version_from_name(name) do
    # OLM CSVs are named like "prometheus-operator.v0.65.1"
    case Regex.run(~r/\.v?(\d+\.\d+\.\d+.*)$/, name) do
      [_, version] -> version
      _ -> nil
    end
  end

  defp parse_operator(name, operator, csv, version) do
    spec = csv["spec"] || %{}
    annotations = get_in(csv, ["metadata", "annotations"]) || %{}
    description_block = spec["description"] || operator["description"]

    # Extract required APIs as dependencies
    _required_apis = spec["apiservicedefinitions"] || %{}
    required_crds = get_in(spec, ["customresourcedefinitions", "required"]) || []

    deps =
      required_crds
      |> Enum.map(fn crd ->
        crd_name = crd["name"] || crd["kind"] || "unknown"
        {crd_name, crd["version"] || "*"}
      end)
      |> Map.new()

    # Extract container images as keywords
    related_images = operator["related_images"] || []

    image_names =
      related_images
      |> Enum.map(fn img -> img["name"] end)
      |> Enum.reject(&is_nil/1)

    provider = get_in(spec, ["provider", "name"])

    manifest = %ManifestFormat{
      name: name,
      version: version,
      description: truncate_description(description_block),
      license: annotations["license"] || operator["license"],
      homepage: annotations["repository"] || operator["homepage"],
      repository: annotations["repository"],
      authors: if(provider, do: [provider], else: []),
      keywords: (operator["categories"] || []) ++ image_names,
      dependencies: deps,
      source_forth: :k8s_operators,
      raw_manifest: operator
    }

    # OLM bundles are distributed as container images
    bundle_image = annotations["containerImage"] || operator["containerImage"]

    %ResolvedPackage{
      package: name,
      version: version,
      forth: :k8s_operators,
      registry_url: "https://operatorhub.io",
      manifest: manifest,
      tarball_url: bundle_image,
      checksum: nil,
      attestations: [],
      resolved_deps: []
    }
  end

  defp truncate_description(nil), do: nil

  defp truncate_description(desc) when byte_size(desc) > 500 do
    String.slice(desc, 0, 497) <> "..."
  end

  defp truncate_description(desc), do: desc

  @doc """
  Search for operators on OperatorHub.io.
  """
  def search(query, _opts \\ []) do
    url = "#{@api_url}/operators?keyword=#{URI.encode(query)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} when is_map(body) ->
        operators = body["operators"] || body["items"] || []

        results =
          operators
          |> Enum.take(20)
          |> Enum.map(fn op ->
            csv = op["csv"] || %{}
            spec = csv["spec"] || %{}

            %{
              name: op["name"] || op["packageName"],
              version: spec["version"] || op["version"],
              description: op["description"] || spec["description"]
            }
          end)

        {:ok, results}

      {:ok, items} when is_list(items) ->
        results =
          items
          |> Enum.take(20)
          |> Enum.map(fn op ->
            %{
              name: op["name"] || op["packageName"],
              version: op["version"],
              description: op["description"]
            }
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if an operator exists on OperatorHub.io.
  """
  def exists?(name) do
    case fetch_package(name) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get available versions (channels) for an operator.
  """
  def versions(name) do
    url = "#{@api_url}/operator/#{URI.encode(name)}"

    case VerifiedHttp.get_json(url, receive_timeout: 10_000) do
      {:ok, body} ->
        operator = body["operator"] || body
        channels = operator["channels"] || []

        vers =
          channels
          |> Enum.flat_map(fn ch ->
            entries = ch["entries"] || ch["versions"] || []

            Enum.map(entries, fn
              e when is_map(e) -> e["version"] || e["name"]
              e when is_binary(e) -> e
              _ -> nil
            end)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        # If no channel entries, fall back to single version
        vers =
          if vers == [] do
            case fetch_package(name) do
              {:ok, pkg} -> [pkg.version]
              _ -> []
            end
          else
            vers
          end

        {:ok, vers}

      {:error, _} = err ->
        err
    end
  end
end
