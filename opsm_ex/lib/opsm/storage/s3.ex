# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Storage.S3 do
  @moduledoc """
  S3-compatible tarball storage backend.

  Uses inline AWS SigV4 signing (no ExAws dependency) and Req for HTTP.
  Compatible with AWS S3, MinIO, Garage, Tigris, Cloudflare R2, and any
  S3-compatible object store.

  Configuration via environment variables:
  - `AWS_ACCESS_KEY_ID`      — required
  - `AWS_SECRET_ACCESS_KEY`  — required
  - `OPSM_S3_BUCKET`         — required (e.g. "my-opsm-cache")
  - `OPSM_S3_REGION`         — default "us-east-1"
  - `OPSM_S3_ENDPOINT`       — default "https://{bucket}.s3.{region}.amazonaws.com"
                                Set to MinIO/Garage/R2 URL for non-AWS stores.

  Key format: `{forth}/{package}-{version}.{ext}` (mirrors the local cache layout).
  """

  @behaviour Opsm.Storage.Backend

  @timeout_ms 60_000

  # ---------------------------------------------------------------------------
  # Backend callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def put(key, local_path, _opts) do
    with {:ok, cfg} <- config(),
         {:ok, body} <- File.read(local_path) do
      content_sha = sha256_hex(body)
      url = object_url(cfg, key)
      now = utc_now_iso()
      date = String.slice(now, 0, 8)

      headers = [
        {"host",                  URI.parse(url).host},
        {"x-amz-content-sha256", content_sha},
        {"x-amz-date",           now},
        {"content-type",         "application/octet-stream"}
      ]

      auth = sigv4_auth("PUT", URI.parse(url).path, "", headers, content_sha, now, date, cfg)
      req_headers = headers ++ [{"authorization", auth}]

      case Req.put(url,
             headers: req_headers,
             body: body,
             receive_timeout: @timeout_ms
           ) do
        {:ok, %{status: s}} when s in 200..299 -> {:ok, key}
        {:ok, %{status: s, body: b}}            -> {:error, "S3 PUT returned #{s}: #{inspect(b)}"}
        {:error, reason}                        -> {:error, "S3 PUT failed: #{inspect(reason)}"}
      end
    else
      {:error, :not_configured} -> {:error, :not_configured}
      {:error, reason}          -> {:error, "S3 PUT: #{inspect(reason)}"}
    end
  end

  @impl true
  def get(key, dest_path, _opts) do
    with {:ok, cfg} <- config() do
      url = object_url(cfg, key)
      now = utc_now_iso()
      date = String.slice(now, 0, 8)
      empty_hash = sha256_hex("")

      headers = [
        {"host",                  URI.parse(url).host},
        {"x-amz-content-sha256", empty_hash},
        {"x-amz-date",           now}
      ]

      auth = sigv4_auth("GET", URI.parse(url).path, "", headers, empty_hash, now, date, cfg)
      req_headers = headers ++ [{"authorization", auth}]

      dest_path |> Path.dirname() |> File.mkdir_p!()

      case Req.get(url,
             headers: req_headers,
             into: File.stream!(dest_path),
             receive_timeout: @timeout_ms
           ) do
        {:ok, %{status: 200}}     -> {:ok, dest_path}
        {:ok, %{status: 404}}     -> {:error, :not_found}
        {:ok, %{status: s}}       -> {:error, "S3 GET returned #{s}"}
        {:error, reason}          -> {:error, "S3 GET failed: #{inspect(reason)}"}
      end
    else
      {:error, :not_configured} -> {:error, :not_configured}
    end
  end

  @impl true
  def exists?(key, _opts) do
    case config() do
      {:error, :not_configured} -> false
      {:ok, cfg} ->
        url = object_url(cfg, key)
        now = utc_now_iso()
        date = String.slice(now, 0, 8)
        empty_hash = sha256_hex("")

        headers = [
          {"host",                  URI.parse(url).host},
          {"x-amz-content-sha256", empty_hash},
          {"x-amz-date",           now}
        ]

        auth = sigv4_auth("HEAD", URI.parse(url).path, "", headers, empty_hash, now, date, cfg)
        req_headers = headers ++ [{"authorization", auth}]

        case Req.head(url, headers: req_headers, receive_timeout: 5_000) do
          {:ok, %{status: 200}} -> true
          _                     -> false
        end
    end
  end

  @impl true
  def url(key, _opts) do
    case config() do
      {:ok, cfg} -> object_url(cfg, key)
      _          -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # SigV4 implementation
  # ---------------------------------------------------------------------------

  defp sigv4_auth(method, path, query_string, headers, payload_hash, amz_date, date, cfg) do
    %{access_key: access_key, secret_key: secret_key, region: region} = cfg

    signed_headers_str = headers |> Enum.map(fn {k, _} -> k end) |> Enum.join(";")

    canonical_headers =
      headers
      |> Enum.map(fn {k, v} -> "#{k}:#{String.trim(v)}\n" end)
      |> Enum.join()

    canonical_request =
      Enum.join(
        [method, path, query_string, canonical_headers, signed_headers_str, payload_hash],
        "\n"
      )

    credential_scope = "#{date}/#{region}/s3/aws4_request"

    string_to_sign =
      Enum.join(
        ["AWS4-HMAC-SHA256", amz_date, credential_scope, sha256_hex(canonical_request)],
        "\n"
      )

    signing_key = derive_signing_key(secret_key, date, region)
    signature = hmac_sha256(signing_key, string_to_sign) |> Base.encode16(case: :lower)

    "AWS4-HMAC-SHA256 Credential=#{access_key}/#{credential_scope}, " <>
      "SignedHeaders=#{signed_headers_str}, Signature=#{signature}"
  end

  defp derive_signing_key(secret_key, date, region) do
    ("AWS4" <> secret_key)
    |> hmac_sha256(date)
    |> hmac_sha256(region)
    |> hmac_sha256("s3")
    |> hmac_sha256("aws4_request")
  end

  defp hmac_sha256(key, data), do: :crypto.mac(:hmac, :sha256, key, data)

  defp sha256_hex(data), do: :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)

  # ---------------------------------------------------------------------------
  # Config and URL helpers
  # ---------------------------------------------------------------------------

  defp config do
    bucket     = System.get_env("OPSM_S3_BUCKET")
    region     = System.get_env("OPSM_S3_REGION", "us-east-1")
    access_key = System.get_env("AWS_ACCESS_KEY_ID")
    secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")

    if bucket && access_key && secret_key do
      endpoint = System.get_env("OPSM_S3_ENDPOINT", "https://#{bucket}.s3.#{region}.amazonaws.com")

      {:ok, %{
        bucket:     bucket,
        region:     region,
        access_key: access_key,
        secret_key: secret_key,
        endpoint:   endpoint
      }}
    else
      {:error, :not_configured}
    end
  end

  defp object_url(%{endpoint: endpoint}, key) do
    "#{String.trim_trailing(endpoint, "/")}/#{key}"
  end

  defp utc_now_iso do
    {{y, mo, d}, {h, mi, s}} = :calendar.universal_time()
    :io_lib.format("~4..0B~2..0B~2..0BT~2..0B~2..0B~2..0BZ", [y, mo, d, h, mi, s])
    |> IO.iodata_to_binary()
  end
end
