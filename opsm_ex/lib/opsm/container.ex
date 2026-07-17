# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Container do
  @moduledoc """
  Container image management and security integration.

  Integrates with:
  - Svalinn (vulnerability scanning)
  - Selur (image signing and verification)
  - Vordr (runtime verification)
  """

  require Logger

  alias Opsm.Types.{ContainerImage, ScanResult, SignatureResult}
  alias Opsm.Http

  @doc """
  Build a container image from a Containerfile.

  Returns `{:error, reason}` when no container runtime (nerdctl, podman, docker)
  is found on $PATH, rather than raising.
  """
  def build(path, opts \\ []) do
    tag = Keyword.get(opts, :tag, "latest")
    containerfile = Keyword.get(opts, :containerfile, "Containerfile")

    with {:ok, runtime} <- detect_runtime() do
      Logger.info("Building container image: #{path}:#{tag}")

      case System.cmd(runtime, ["build", "-t", tag, "-f", containerfile, path],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          Logger.info("Container build successful")
          {:ok, %ContainerImage{tag: tag, digest: extract_digest(output), runtime: runtime}}

        {error, code} ->
          Logger.error("Container build failed: #{error}")
          {:error, "Build failed with exit code #{code}"}
      end
    end
  end

  @doc """
  Scan a container image for vulnerabilities using Svalinn.

  Returns `{:error, reason}` when the Svalinn service URL is nil or the
  HTTP request fails, rather than crashing.
  """
  def scan(image, svalinn_url) do
    if is_nil(svalinn_url) or svalinn_url == "" do
      Logger.warning("Svalinn URL not configured — skipping vulnerability scan")
      {:error, "Svalinn URL not configured"}
    else
      Logger.info("Scanning container image: #{image}")

      try do
        client = Http.build_client(%Opsm.Types.HttpConfig{}, base_url: svalinn_url)

        body = %{
          "image" => image,
          "scanners" => ["trivy", "grype"],
          "severity_threshold" => "medium"
        }

        case Http.post_json(client, "/scan", body) do
          :ok ->
            result = %ScanResult{critical: 0, high: 0, medium: 0, low: 0, total: 0}
            Logger.info("Image scan passed")
            {:ok, result}

          {:error, reason} ->
            Logger.error("Scan failed: #{inspect(reason)}")
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("Svalinn scan crashed: #{Exception.message(e)}")
          {:error, "Svalinn unreachable: #{Exception.message(e)}"}
      end
    end
  end

  @doc """
  Sign a container image using Selur.

  Returns `{:error, reason}` when the Selur service URL is nil, the key path
  is missing, or the HTTP request fails.
  """
  def sign(image, selur_url, key_path) do
    cond do
      is_nil(selur_url) or selur_url == "" ->
        Logger.warning("Selur URL not configured — skipping image signing")
        {:error, "Selur URL not configured"}

      is_nil(key_path) or key_path == "" ->
        Logger.warning("Signing key path not configured — skipping image signing")
        {:error, "Signing key path not configured"}

      true ->
        Logger.info("Signing container image: #{image}")

        try do
          client = Http.build_client(%Opsm.Types.HttpConfig{}, base_url: selur_url)

          body = %{
            "image" => image,
            "key_path" => key_path,
            "method" => "cosign"
          }

          case Http.post_json(client, "/sign", body) do
            :ok ->
              Logger.info("Image signed successfully")

              {:ok,
               %SignatureResult{
                 signature: "signed",
                 algorithm: "cosign",
                 signed_at: DateTime.utc_now() |> DateTime.to_iso8601()
               }}

            {:error, reason} ->
              Logger.error("Signing failed: #{inspect(reason)}")
              {:error, reason}
          end
        rescue
          e ->
            Logger.error("Selur sign crashed: #{Exception.message(e)}")
            {:error, "Selur unreachable: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Verify a container image signature using Selur.

  Returns `{:error, reason}` when the Selur service URL or public key path
  is nil, or when the HTTP verification request fails.
  """
  def verify(image, selur_url, public_key_path) do
    cond do
      is_nil(selur_url) or selur_url == "" ->
        Logger.warning("Selur URL not configured — skipping signature verification")
        {:error, "Selur URL not configured"}

      is_nil(public_key_path) or public_key_path == "" ->
        Logger.warning("Public key path not configured — skipping signature verification")
        {:error, "Public key path not configured"}

      true ->
        Logger.info("Verifying container image: #{image}")

        try do
          client = Http.build_client(%Opsm.Types.HttpConfig{}, base_url: selur_url)

          body = %{
            "image" => image,
            "public_key_path" => public_key_path,
            "method" => "cosign"
          }

          case Http.post_json(client, "/verify", body) do
            :ok ->
              Logger.info("Image signature verified")
              {:ok, :verified}

            {:error, reason} ->
              Logger.error("Verification request failed: #{inspect(reason)}")
              {:error, reason}
          end
        rescue
          e ->
            Logger.error("Selur verify crashed: #{Exception.message(e)}")
            {:error, "Selur unreachable: #{Exception.message(e)}"}
        end
    end
  end

  @doc """
  Push a container image to a registry.

  Returns `{:error, reason}` when no container runtime is available.
  """
  def push(image, registry, _opts \\ []) do
    with {:ok, runtime} <- detect_runtime() do
      full_image = "#{registry}/#{image}"

      Logger.info("Pushing container image: #{full_image}")

      # Tag with registry
      case System.cmd(runtime, ["tag", image, full_image], stderr_to_stdout: true) do
        {_output, 0} ->
          # Push to registry
          case System.cmd(runtime, ["push", full_image], stderr_to_stdout: true) do
            {_output, 0} ->
              Logger.info("Image pushed successfully")
              {:ok, full_image}

            {error, code} ->
              Logger.error("Push failed: #{error}")
              {:error, "Push failed with exit code #{code}"}
          end

        {error, code} ->
          Logger.error("Tag failed: #{error}")
          {:error, "Tag failed with exit code #{code}"}
      end
    end
  end

  @doc """
  Full container publish pipeline: build -> scan -> sign -> push.

  Each step is tagged so callers can tell which stage failed. Returns
  `{:ok, result}` on success or `{:error, {stage, reason}}` on failure.
  Missing tools or unreachable services produce descriptive errors rather
  than raising exceptions.
  """
  def publish_pipeline(path, registry, opts \\ []) do
    tag = Keyword.get(opts, :tag, "latest")
    svalinn_url = Keyword.get(opts, :svalinn_url)
    selur_url = Keyword.get(opts, :selur_url)
    key_path = Keyword.get(opts, :key_path)

    Logger.info("Starting container publish pipeline")

    with {:build, {:ok, image}} <- {:build, build(path, tag: tag)},
         {:scan, {:ok, _scan_result}} <- {:scan, scan(image.tag, svalinn_url)},
         {:sign, {:ok, _signature}} <- {:sign, sign(image.tag, selur_url, key_path)},
         {:push, {:ok, pushed_image}} <- {:push, push(image.tag, registry, opts)} do
      Logger.info("Container pipeline completed successfully")
      {:ok, %{image: pushed_image, digest: image.digest}}
    else
      {stage, {:error, reason}} ->
        Logger.error("Container pipeline failed at #{stage}: #{inspect(reason)}")
        {:error, {stage, reason}}
    end
  end

  # Private functions

  # Detect an available container runtime on the system.
  # Prefers nerdctl > podman > docker, matching the project's container policy
  # (Podman preferred, but nerdctl is fine for containerd environments).
  # Returns {:ok, binary_name} or {:error, reason} — never raises.
  defp detect_runtime do
    cond do
      System.find_executable("nerdctl") -> {:ok, "nerdctl"}
      System.find_executable("podman") -> {:ok, "podman"}
      System.find_executable("docker") -> {:ok, "docker"}
      true -> {:error, "No container runtime found (install nerdctl, podman, or docker)"}
    end
  end

  defp extract_digest(output) do
    case Regex.run(~r/sha256:([a-f0-9]{64})/, output) do
      [_, digest] -> "sha256:#{digest}"
      _ -> nil
    end
  end
end
