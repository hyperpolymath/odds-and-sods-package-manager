# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.ManifestIngestion do
  @moduledoc """
  Manifest ingestion pipeline: nickel-config-reporter validation, IMP normalization, and
  HAR staging via the `opm-har-ingest` queue.
  """

  require Logger

  alias Opm.{Imp, ManifestFinder, RegistryGateway}
  alias Opm.Federation

  @har_queue_dir Path.join(System.tmp_dir!(), "opm-har-ingest")

  @spec ingest(String.t()) :: {:ok, map()} | {:error, String.t()}
  def ingest(path) do
    with {:ok, manifest_path} <- ManifestFinder.locate(path),
         {:ok, manifest} <- Federation.convert_manifest(manifest_path),
         {:ok, digest} <- compute_sha256(manifest_path),
         :ok <- validate_with_nickel(manifest_path),
         {:ok, imp} <- Imp.normalize(manifest, manifest_path, digest),
         :ok <- stage_for_har(imp, manifest_path, digest),
         {:ok, _entry} <- RegistryGateway.publish(manifest, imp, digest) do
      {:ok,
       %{
         manifest: manifest,
         imp: imp,
         digest: digest,
         manifest_path: manifest_path
       }}
    end
  end

  defp compute_sha256(path) do
    case File.read(path) do
      {:ok, content} ->
        digest = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
        {:ok, "sha256:#{digest}"}

      {:error, reason} ->
        {:error, "Failed to read artifact for digest (#{inspect(reason)})"}
    end
  end

  defp validate_with_nickel(manifest_path) do
    case System.find_executable("nickel-config-reporter") do
      nil ->
        Logger.debug("nickel-config-reporter not installed; skipping manifest validation")
        :ok

      executable ->
        run_command(
          executable,
          ["validate", manifest_path],
          "nickel-config-reporter"
        )
    end
  end

  defp stage_for_har(imp, manifest_path, digest) do
    payload = %{
      "imp" => imp,
      "manifestPath" => manifest_path,
      "digest" => digest,
      "ingestedAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    File.mkdir_p!(@har_queue_dir)

    filename =
      manifest_path
      |> Path.basename()
      |> Path.rootname()
      |> Kernel.<>(".imp.json")

    file_path = Path.join(@har_queue_dir, filename)
    File.write(file_path, Jason.encode!(payload))
  end

  defp run_command(executable, args, label) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {stderr, _} -> {:error, "#{label} failed: #{String.trim(stderr)}"}
    end
  end
end
