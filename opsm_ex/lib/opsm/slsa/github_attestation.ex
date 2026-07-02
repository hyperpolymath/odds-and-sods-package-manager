# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Slsa.GithubAttestation do
  @moduledoc """
  Fetch and verify GitHub native build-provenance attestations.

  GitHub's `actions/attest-build-provenance` produces Sigstore bundles
  (DSSE envelope + Fulcio certificate + Rekor/TSA proof) that GitHub stores
  against the artifact digest and serves from
  `GET /repos/{owner}/{repo}/attestations/{subject-digest}`.

  Trust model (issue #56): the GitHub Actions builder identity
  (`https://github.com/<owner>/<repo>/.github/workflows/<wf>@<ref>`) is
  trusted ONLY after the Sigstore bundle has been cryptographically
  verified — never from the builder string alone. Bundle verification is
  delegated to checky-monkey's `/verify/github-attestation` endpoint
  (which wraps `gh attestation verify`), with a local `gh` CLI fallback
  via SafeExec when the service is unreachable.
  """

  alias Opsm.Verified.Http, as: VerifiedHttp
  alias Opsm.Verified.Json
  alias Opsm.Clients.CheckyMonkey
  alias Opsm.SafeExec
  alias Opsm.Types.GithubAttestationVerification

  @api_base "https://api.github.com"
  @api_version "2022-11-28"

  # GitHub Actions workflow builder identity, e.g.
  # https://github.com/hyperpolymath/proven/.github/workflows/release.yml@refs/heads/main
  @github_actions_builder ~r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/\.github/workflows/[^@\s]+@\S+\z}

  @owner_repo_pattern ~r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}
  @sha256_hex ~r/\A[0-9a-f]{64}\z/

  # ==========================================================================
  # Builder identity
  # ==========================================================================

  @doc """
  True when the builder ID has the GitHub Actions native-builder shape.

  This predicate alone confers no trust — callers must combine it with a
  successful bundle verification (see `Opsm.Slsa.Provenance.verify_github_attestation/2`).
  """
  def github_actions_builder?(builder_id) when is_binary(builder_id) do
    Regex.match?(@github_actions_builder, builder_id)
  end

  def github_actions_builder?(_), do: false

  # ==========================================================================
  # Fetch (GitHub attestations API)
  # ==========================================================================

  @doc """
  Fetch the attestation records GitHub holds for an artifact digest.

  `owner_repo` is `"owner/repo"`; `digest` is `"sha256:<64-hex>"` or bare hex.
  Returns `{:ok, [attestation_record]}` (possibly empty) or `{:error, reason}`.

  Each record may carry the Sigstore bundle inline under `"bundle"` or only
  as a `"bundle_url"` (a snappy-compressed blob — NOT fetched here). This
  call establishes existence; cryptographic verification and statement
  extraction happen in `verify_subject/4`, whose `gh attestation verify`
  backend fetches and decompresses bundles itself.
  """
  def fetch_attestations(owner_repo, digest, opts \\ []) do
    with {:ok, owner_repo} <- validate_owner_repo(owner_repo),
         {:ok, digest} <- normalize_digest(digest) do
      api_base = Keyword.get(opts, :api_base, @api_base)
      url = "#{api_base}/repos/#{owner_repo}/attestations/#{digest}"
      timeout = Keyword.get(opts, :timeout, 10_000)

      case VerifiedHttp.get_json(url, headers: github_headers(), timeout: timeout) do
        {:ok, %{"attestations" => attestations}} when is_list(attestations) ->
          {:ok, attestations}

        {:ok, _other} ->
          {:ok, []}

        # GitHub returns 404 when no attestations exist for the digest
        {:error, {:http_error, 404}} ->
          {:ok, []}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  The Sigstore bundle carried inline by an attestation record, when present
  (a map, or a JSON-encoded string). Records that only carry a `bundle_url`
  (snappy-compressed blob) yield `nil`.
  """
  def bundle_from_record(%{"bundle" => bundle}) when is_map(bundle), do: bundle

  def bundle_from_record(%{"bundle" => bundle}) when is_binary(bundle) do
    case Json.decode(bundle) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> nil
    end
  end

  def bundle_from_record(_record), do: nil

  @doc """
  Decode the in-toto statement out of a Sigstore bundle's DSSE envelope.
  """
  def extract_statement(%{"dsseEnvelope" => %{"payloadType" => ptype, "payload" => payload}})
      when is_binary(payload) do
    if ptype == "application/vnd.in-toto+json" do
      with {:ok, raw} <- decode_base64(payload),
           {:ok, statement} <- Json.decode(raw) do
        {:ok, statement}
      end
    else
      {:error, "Unsupported DSSE payload type: #{ptype}"}
    end
  end

  def extract_statement(_bundle), do: {:error, "Bundle has no DSSE envelope"}

  # ==========================================================================
  # Verify (checky-monkey service, local gh fallback)
  # ==========================================================================

  @doc """
  Fetch and verify GitHub attestations for a resolved package.

  Returns:
  - `{:ok, %GithubAttestationVerification{}}` — bundle checked (see `.verified`)
  - `{:unverified, msg}` — attestations exist but no verifier was reachable
  - `{:none, msg}` — nothing to check (no GitHub repo / digest / attestations)
  - `{:error, reason}` — the attestation lookup itself failed
  """
  def verify_package(package, config, opts \\ []) do
    with {:ok, owner_repo} <- github_owner_repo(package),
         {:ok, digest} <- artifact_digest(package) do
      case fetch_attestations(owner_repo, digest, opts) do
        {:ok, []} ->
          {:none, "No GitHub attestations found for #{owner_repo}@#{short_digest(digest)}"}

        {:ok, bundles} ->
          subject = verification_subject(package, opts)
          verify_subject(subject, owner_repo, config, Keyword.put(opts, :bundle_count, length(bundles)))

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Verify a subject (`oci://` URI, `{:artifact, path}`, or `nil`) against the
  repo's GitHub attestations. Tries checky-monkey first, then a local
  `gh attestation verify` via SafeExec. With no subject available the bundle
  cannot be cryptographically checked — returns `{:unverified, msg}`.
  """
  def verify_subject(nil, owner_repo, _config, opts) do
    count = Keyword.get(opts, :bundle_count, 1)

    {:unverified,
     "#{count} GitHub attestation(s) found for #{owner_repo} " <>
       "(no artifact subject available for cryptographic verification)"}
  end

  def verify_subject(subject, owner_repo, config, opts) do
    with {:ok, owner_repo} <- validate_owner_repo(owner_repo) do
      case verify_via_service(subject, owner_repo, config) do
        {:ok, verification} ->
          {:ok, verification}

        {:error, _service_reason} ->
          case verify_via_local_gh(subject, owner_repo, opts) do
            {:ok, verification} ->
              {:ok, verification}

            {:error, reason} ->
              count = Keyword.get(opts, :bundle_count, 1)

              {:unverified,
               "#{count} GitHub attestation(s) found for #{owner_repo} " <>
                 "but no verifier available (#{reason})"}
          end
      end
    end
  end

  defp verify_via_service(subject, owner_repo, config) do
    client = CheckyMonkey.new(config.checky_monkey, config.http)

    request =
      case subject do
        {:artifact, path} -> %{owner_repo: owner_repo, artifact_path: path}
        oci when is_binary(oci) -> %{owner_repo: owner_repo, oci_uri: oci}
      end

    CheckyMonkey.verify_github_attestation(client, request)
  end

  defp verify_via_local_gh(subject, owner_repo, opts) do
    positional =
      case subject do
        {:artifact, path} -> path
        oci when is_binary(oci) -> oci
      end

    args = ["attestation", "verify", positional, "--repo", owner_repo, "--format", "json"]
    allowlist = Keyword.get(opts, :exec_allowlist, ["gh"])

    case SafeExec.cmd("gh", args, allowlist: allowlist) do
      {output, 0} ->
        case Json.decode(output) do
          {:ok, results} -> {:ok, decode_gh_output(results)}
          {:error, _} -> {:error, "gh produced unparseable output"}
        end

      {output, _nonzero} ->
        message = output |> to_string() |> String.trim() |> String.slice(0, 300)

        if String.contains?(message, "safe-exec blocked") or
             String.contains?(message, "not found") do
          {:error, "gh CLI unavailable: #{message}"}
        else
          # gh ran and rejected the attestation — that is a definitive failure
          {:ok,
           %GithubAttestationVerification{
             verified: false,
             message: "gh attestation verify failed: #{message}"
           }}
        end
    end
  end

  @doc """
  Map `gh attestation verify --format json` output (a list of verification
  results) to a `GithubAttestationVerification`.
  """
  def decode_gh_output(results) when is_list(results) and results != [] do
    statement =
      results
      |> Enum.map(&get_in_any(&1, [["verificationResult", "statement"], ["statement"]]))
      |> Enum.find(&is_map/1)

    builder_id =
      case statement do
        %{"predicate" => %{"runDetails" => %{"builder" => %{"id" => id}}}} -> id
        _ -> nil
      end

    %GithubAttestationVerification{
      verified: true,
      builder_id: builder_id,
      predicate_type: statement && statement["predicateType"],
      message: "Verified via gh attestation verify (#{length(results)} attestation(s))",
      details: %{statement: statement}
    }
  end

  def decode_gh_output(_),
    do: %GithubAttestationVerification{verified: false, message: "gh returned no verification results"}

  # ==========================================================================
  # Package helpers
  # ==========================================================================

  @doc """
  Extract `"owner/repo"` from a package's manifest repository URL.
  """
  def github_owner_repo(%{manifest: %{repository: repo}}) when is_binary(repo) do
    case Regex.run(~r{\Ahttps?://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(?:\.git)?/?\z}, repo) do
      [_, owner, name] -> {:ok, "#{owner}/#{name}"}
      _ -> {:none, "Package repository is not a GitHub URL"}
    end
  end

  def github_owner_repo(_package), do: {:none, "Package has no repository URL"}

  @doc """
  The `sha256:<hex>` artifact digest for attestation lookup, from the
  package checksum. Only sha256 checksums are usable.
  """
  def artifact_digest(%{checksum: checksum, checksum_algo: algo})
      when is_binary(checksum) and algo in [:sha256, "sha256"] do
    case normalize_digest(checksum) do
      {:ok, digest} -> {:ok, digest}
      {:error, _} -> {:none, "Package checksum is not a sha256 digest"}
    end
  end

  def artifact_digest(_package), do: {:none, "Package has no sha256 checksum for attestation lookup"}

  defp verification_subject(package, opts) do
    cond do
      Keyword.has_key?(opts, :artifact_path) ->
        {:artifact, Keyword.fetch!(opts, :artifact_path)}

      is_binary(package.tarball_url) and String.starts_with?(package.tarball_url, "oci://") ->
        package.tarball_url

      true ->
        nil
    end
  end

  # ==========================================================================
  # Validation / small helpers
  # ==========================================================================

  defp validate_owner_repo(owner_repo) when is_binary(owner_repo) do
    if Regex.match?(@owner_repo_pattern, owner_repo) do
      {:ok, owner_repo}
    else
      {:error, "Invalid owner/repo: #{inspect(owner_repo)}"}
    end
  end

  defp validate_owner_repo(other), do: {:error, "Invalid owner/repo: #{inspect(other)}"}

  defp normalize_digest("sha256:" <> hex), do: normalize_digest(hex)

  defp normalize_digest(hex) when is_binary(hex) do
    normalized = String.downcase(hex)

    if Regex.match?(@sha256_hex, normalized) do
      {:ok, "sha256:#{normalized}"}
    else
      {:error, "Not a sha256 digest: #{inspect(hex)}"}
    end
  end

  defp normalize_digest(other), do: {:error, "Not a sha256 digest: #{inspect(other)}"}

  defp short_digest("sha256:" <> hex), do: "sha256:#{String.slice(hex, 0, 12)}…"
  defp short_digest(other), do: other

  defp decode_base64(payload) do
    case Base.decode64(payload) do
      {:ok, raw} -> {:ok, raw}
      :error -> {:error, "DSSE payload is not valid base64"}
    end
  end

  defp get_in_any(map, paths) do
    Enum.find_value(paths, fn path -> get_in(map, path) end)
  end

  defp github_headers do
    token = System.get_env("GITHUB_TOKEN") || Application.get_env(:opsm, :github_token, nil)

    base = [
      {"Accept", "application/vnd.github+json"},
      {"X-GitHub-Api-Version", @api_version}
    ]

    if token do
      [{"Authorization", "Bearer #{token}"} | base]
    else
      base
    end
  end
end
