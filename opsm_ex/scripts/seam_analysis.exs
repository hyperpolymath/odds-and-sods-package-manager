# SPDX-License-Identifier: PMPL-1.0

defmodule Opsm.SeamAnalysis do
  @moduledoc """
  Run seam analysis: ingest multiple manifests, verify HAR staging + registry gateway, and surface timings.
  """

  @report_file Path.join(["reports", "seam_analysis.csv"])
  @har_queue_dir Path.join(System.tmp_dir!(), "opsm-har-ingest")

  def run(iterations \\ 5) do
    Application.ensure_all_started(:opsm)

    client = Req.new(base_url: "http://127.0.0.1:4050")

    1..iterations
    |> Enum.each(fn i ->
      temp_dir = Path.join(System.tmp_dir!(), "opsm_seam_#{i}")
      File.mkdir_p!(temp_dir)
      manifest_path = Path.join(temp_dir, "package.json")

      manifest = %{
        "name" => "seam-test-#{i}",
        "version" => "0.1.#{i}",
        "license" => "MIT",
        "dependencies" => %{"dep-#{i}" => ">= 0.0.1"}
      }

      File.write!(manifest_path, Jason.encode!(manifest))

      start = System.monotonic_time(:millisecond)
      result = Opsm.ManifestIngestion.ingest(manifest_path)
      duration = System.monotonic_time(:millisecond) - start

      IO.puts("Iteration #{i}: duration #{duration} ms")

      case result do
        {:ok, %{manifest: manifest, digest: digest, imp: imp}} ->
          manifest_map = manifest_to_map(manifest)
          IO.puts("  manifest: #{manifest_map["name"]}@#{manifest_map["version"]}")
          IO.puts("  digest: #{digest}")
          fetch_from_gateway(client, manifest_map["name"])
          log_iteration(i, duration, manifest_map, digest, imp)

        {:error, reason} ->
          IO.puts("  ingest failed: #{reason}")
      end

      File.rm_rf!(temp_dir)
    end)
  end

  defp fetch_from_gateway(client, name) do
    case Req.get(client, url: "/packages/#{name}") do
      {:ok, %Req.Response{status: 200, body: body}} ->
        data = Jason.decode!(body)
        IO.puts("  gateway digest: #{data["digest"]}")

      {:ok, %Req.Response{status: status}} ->
        IO.puts("  gateway returned status #{status}")

      {:error, reason} ->
        IO.puts("  gateway request failed: #{inspect(reason)}")
    end
  end

  defp log_iteration(iteration, duration, manifest, digest, imp) do
    File.mkdir_p!(Path.dirname(@report_file))

    header = "timestamp,iteration,duration_ms,package,version,digest,gateway_status,har_files,ingested_at\n"
    append_header(header)

    status = gather_gateway_status(manifest["name"])
    har_files = gather_har_files()
    ingested_at = get_in(imp, ["provenance", "ingestedAt"]) || ""

    line =
      [
        DateTime.utc_now() |> DateTime.to_iso8601(),
        iteration,
        duration,
        manifest["name"],
        manifest["version"],
        digest,
        status,
        har_files,
        ingested_at
      ]
      |> Enum.map(&to_string/1)
      |> Enum.join(",")

    File.write!(@report_file, line <> "\n", [:append])
  end

  defp append_header(header) do
    unless File.exists?(@report_file) do
      File.write!(@report_file, header)
    end
  end

  defp gather_gateway_status(name) do
    case Req.get(Req.new(base_url: "http://127.0.0.1:4050"), url: "/packages/#{name}") do
      {:ok, %Req.Response{status: 200}} -> "ok"
      {:ok, %Req.Response{status: status}} -> "status_#{status}"
      _ -> "error"
    end
  end

  defp gather_har_files do
    case File.ls(@har_queue_dir) do
      {:ok, files} -> "#{length(files)}"
      {:error, _} -> "0"
    end
  end

  defp manifest_to_map(manifest) when is_struct(manifest) do
    manifest
    |> Map.from_struct()
    |> Map.delete(:__struct__)
    |> stringify_keys()
  end

  defp manifest_to_map(manifest) when is_map(manifest) do
    manifest
    |> stringify_keys()
  end

  defp stringify_keys(map) do
    map
    |> Enum.map(fn {key, value} -> {to_string(key), value} end)
    |> Map.new()
  end
end

Opsm.SeamAnalysis.run(5)
