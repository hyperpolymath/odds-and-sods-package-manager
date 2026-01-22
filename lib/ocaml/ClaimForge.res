// SPDX-License-Identifier: PMPL-1.0
// ClaimForge.res - Attestation generation client

open Types

// =============================================================================
// HTTP Client Type
// =============================================================================

type t = {
  baseUrl: string,
  token: option<string>,
  opts: httpOptions,
}

let make = (baseUrl: string, token: option<string>, opts: httpOptions): t => {
  baseUrl,
  token,
  opts,
}

// =============================================================================
// Deno Command FFI for CLI fallback
// =============================================================================

module DenoCommand = {
  type commandOptions = {
    args: array<string>,
    stdout: string,
    stderr: string,
  }

  type commandOutput = {
    code: int,
    stdout: Uint8Array.t,
    stderr: Uint8Array.t,
  }

  type command

  @new @scope("Deno") external makeCommand: (string, commandOptions) => command = "Command"
  @send external output: command => promise<commandOutput> = "output"
}

module TextDecoder = {
  type t

  @new external make: unit => t = "TextDecoder"
  @send external decode: (t, Uint8Array.t) => string = "decode"
}

// =============================================================================
// JSON Encoding
// =============================================================================

let encodeClaimType = (t: claimType): string => {
  switch t {
  | BuildProvenance => "build-provenance"
  | SourceAttestation => "source-attestation"
  | VulnerabilityScan => "vulnerability-scan"
  | LicenseCompliance => "license-compliance"
  | CodeReview => "code-review"
  }
}

let decodeClaimType = (s: string): claimType => {
  switch s {
  | "build-provenance" => BuildProvenance
  | "source-attestation" => SourceAttestation
  | "vulnerability-scan" => VulnerabilityScan
  | "license-compliance" => LicenseCompliance
  | "code-review" => CodeReview
  | _ => BuildProvenance
  }
}

let encodeAttestRequest = (req: claimForgeRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("artifactPath", req.artifactPath->JSON.Encode.string)
  obj->Dict.set("artifactDigest", req.artifactDigest->JSON.Encode.string)
  obj->Dict.set("claimType", req.claimType->encodeClaimType->JSON.Encode.string)
  switch req.metadata {
  | Some(m) => obj->Dict.set("metadata", m->JSON.Encode.object)
  | None => ()
  }
  obj->JSON.Encode.object->JSON.stringify
}

let encodeVerifyRequest = (req: claimVerifyRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("attestationUri", req.attestationUri->JSON.Encode.string)
  obj->Dict.set("artifactDigest", req.artifactDigest->JSON.Encode.string)
  obj->JSON.Encode.object->JSON.stringify
}

// =============================================================================
// HTTP API Methods
// =============================================================================

let attest = async (client: t, request: claimForgeRequest): result<claimForgeResponse> => {
  let body = encodeAttestRequest(request)

  switch await Http.postJson(client.baseUrl, "/attest", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let digest = request.artifactDigest->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/attestations/${digest}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        Ok({
          attestationId: "",
          claimType: request.claimType,
          createdAt: "",
          expiresAt: None,
          attestationUri: "",
          signature: "",
          publicKeyId: "",
        })
      }
    }
  }
}

let verify = async (client: t, request: claimVerifyRequest): result<claimVerifyResponse> => {
  let body = encodeVerifyRequest(request)

  switch await Http.postJson(client.baseUrl, "/verify", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let uri = request.attestationUri->encodeURIComponent
      switch await Http.getJson(client.baseUrl, `/verify/${uri}`, client.token, client.opts) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        Ok({
          valid: true,
          claimType: BuildProvenance,
          issuer: "",
          issuedAt: "",
          errors: None,
        })
      }
    }
  }
}

let listClaimTypes = async (client: t): result<array<claimType>> => {
  switch await Http.getJson(client.baseUrl, "/claim-types", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok([BuildProvenance, SourceAttestation, VulnerabilityScan, LicenseCompliance, CodeReview])
  }
}

let getAttestation = async (client: t, attestationId: string): result<claimForgeResponse> => {
  let path = `/attestations/${attestationId->encodeURIComponent}`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      attestationId,
      claimType: BuildProvenance,
      createdAt: "",
      expiresAt: None,
      attestationUri: "",
      signature: "",
      publicKeyId: "",
    })
  }
}

// =============================================================================
// CLI Fallback
// =============================================================================

type cli = {binaryPath: string}

let makeCli = (~binaryPath: string="claim-forge"): cli => {
  binaryPath: binaryPath,
}

let cliAttest = async (
  cli: cli,
  artifactPath: string,
  claimType: claimType,
  outputPath: option<string>,
): result<string> => {
  let args = ["attest", "--type", claimType->encodeClaimType, "--artifact", artifactPath]
  let args = switch outputPath {
  | Some(p) => args->Array.concat(["--output", p])
  | None => args
  }

  try {
    let cmd = DenoCommand.makeCommand(
      cli.binaryPath,
      {
        args,
        stdout: "piped",
        stderr: "piped",
      },
    )

    let output = await cmd->DenoCommand.output
    let decoder = TextDecoder.make()

    if output.code != 0 {
      let errorText = decoder->TextDecoder.decode(output.stderr)
      Error(`claim-forge failed: ${errorText}`)
    } else {
      let outputText = decoder->TextDecoder.decode(output.stdout)
      Ok(outputText->String.trim)
    }
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}

let cliVerify = async (cli: cli, attestationPath: string, artifactPath: string): result<bool> => {
  let args = ["verify", "--attestation", attestationPath, "--artifact", artifactPath]

  try {
    let cmd = DenoCommand.makeCommand(
      cli.binaryPath,
      {
        args,
        stdout: "piped",
        stderr: "piped",
      },
    )

    let output = await cmd->DenoCommand.output
    let decoder = TextDecoder.make()

    if output.code != 0 {
      let errorText = decoder->TextDecoder.decode(output.stderr)
      Error(`verification failed: ${errorText}`)
    } else {
      Ok(true)
    }
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}
