// SPDX-License-Identifier: PMPL-1.0
// Palimpsest.res - License analysis client

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
// Additional Types
// =============================================================================

type compatibilityDirection = Both | L1ToL2 | L2ToL1

type compatibilityResult = {
  license1: string,
  license2: string,
  compatible: bool,
  direction: option<compatibilityDirection>,
  reason: option<string>,
}

type copyleftStrength = Weak | Strong | Network

type licenseInfo = {
  spdxId: string,
  name: string,
  url: string,
  osiApproved: bool,
  fsfLibre: bool,
  copyleft: bool,
  copyleftStrength: option<copyleftStrength>,
  permissions: array<string>,
  conditions: array<string>,
  limitations: array<string>,
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

let encodeAnalyzeRequest = (req: palimpsestRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("artifactPath", req.artifactPath->JSON.Encode.string)
  switch req.includeTransitive {
  | Some(b) => obj->Dict.set("includeTransitive", b->JSON.Encode.bool)
  | None => ()
  }
  switch req.targetLicense {
  | Some(l) => obj->Dict.set("targetLicense", l->JSON.Encode.string)
  | None => ()
  }
  obj->JSON.Encode.object->JSON.stringify
}

let encodeCompatibilityRequest = (license1: string, license2: string): string => {
  let obj = Dict.make()
  obj->Dict.set("license1", license1->JSON.Encode.string)
  obj->Dict.set("license2", license2->JSON.Encode.string)
  obj->JSON.Encode.object->JSON.stringify
}

// =============================================================================
// API Methods
// =============================================================================

let analyze = async (client: t, request: palimpsestRequest): result<palimpsestResponse> => {
  let body = encodeAnalyzeRequest(request)

  switch await Http.postJson(client.baseUrl, "/analyze", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let encodedPath = request.artifactPath->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/analyze/${encodedPath}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        Ok({
          analyzedAt: "",
          detectedLicenses: [],
          compatibility: {
            compatible: true,
            targetLicense: request.targetLicense,
            conflicts: [],
          },
          obligations: [],
          risks: [],
        })
      }
    }
  }
}

let checkCompatibility = async (client: t, license1: string, license2: string): result<
  compatibilityResult,
> => {
  let body = encodeCompatibilityRequest(license1, license2)

  switch await Http.postJson(client.baseUrl, "/compatibility", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let l1 = license1->encodeURIComponent
      let l2 = license2->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/compatibility/${l1}/${l2}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        Ok({
          license1,
          license2,
          compatible: true,
          direction: Some(Both),
          reason: None,
        })
      }
    }
  }
}

let getLicenseInfo = async (client: t, spdxId: string): result<licenseInfo> => {
  let path = `/licenses/${spdxId->encodeURIComponent}`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      spdxId,
      name: "",
      url: "",
      osiApproved: false,
      fsfLibre: false,
      copyleft: false,
      copyleftStrength: None,
      permissions: [],
      conditions: [],
      limitations: [],
    })
  }
}

let listLicenses = async (client: t): result<array<string>> => {
  switch await Http.getJson(client.baseUrl, "/licenses", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) => Ok([])
  }
}

// =============================================================================
// CLI Fallback
// =============================================================================

type cli = {binaryPath: string}

let makeCli = (~binaryPath: string="palimpsest-license"): cli => {
  binaryPath: binaryPath,
}

let cliAnalyze = async (cli: cli, artifactPath: string, includeTransitive: bool): result<
  string,
> => {
  let args = ["analyze", artifactPath]
  let args = if includeTransitive {
    args->Array.concat(["--transitive"])
  } else {
    args
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
      Error(`palimpsest-license failed: ${errorText}`)
    } else {
      let outputText = decoder->TextDecoder.decode(output.stdout)
      Ok(outputText)
    }
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}

let cliCheckCompatibility = async (cli: cli, license1: string, license2: string): result<bool> => {
  let args = ["check", license1, license2]

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
      Error(`compatibility check failed: ${errorText}`)
    } else {
      Ok(true)
    }
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Unknown error"))
  }
}
