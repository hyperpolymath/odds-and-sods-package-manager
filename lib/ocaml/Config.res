// SPDX-License-Identifier: PMPL-1.0
@@warning("-44-45")
open Types

// =============================================================================
// Deno FFI Bindings
// =============================================================================

module Deno = {
  module Env = {
    @val @scope(("Deno", "env")) external get: string => option<string> = "get"
  }

  @val @scope("Deno") external readTextFile: string => promise<string> = "readTextFile"

  type fileInfo
  @val @scope("Deno") external stat: string => promise<fileInfo> = "stat"
}

// =============================================================================
// TOML FFI Bindings
// =============================================================================

module Toml = {
  @module("@std/toml") external parse: string => Dict.t<JSON.t> = "parse"
}

// =============================================================================
// Path FFI Bindings
// =============================================================================

module Path = {
  @module("@std/path") @variadic external join: array<string> => string = "join"
}

// =============================================================================
// Proven FFI Bindings
// =============================================================================

module Proven = {
  module SafeUrl = {
    type parseResult = {ok: bool, error: option<string>}

    @module("@proven/mod.ts") @scope("SafeUrl")
    external parse: string => parseResult = "parse"
  }
}

// =============================================================================
// Default Configuration
// =============================================================================

let defaultHttpConfig: httpConfig = {
  timeoutMs: 3000,
  retries: 2,
  backoffMs: 200,
}

let defaultServiceConfig = (port: int): serviceConfig => {
  baseUrl: `http://127.0.0.1:${port->Int.toString}`,
  token: None,
}

let exampleConfig = (): opsmConfig => {
  http: defaultHttpConfig,
  claimForge: defaultServiceConfig(7001),
  checkyMonkey: defaultServiceConfig(7002),
  palimpsestLicense: defaultServiceConfig(7003),
  cicdHyperA: defaultServiceConfig(7004),
  oikos: defaultServiceConfig(7005),
}

// =============================================================================
// URL Validation
// =============================================================================

let validateServiceUrl = (url: string, serviceName: string): result<string> => {
  let parsed = Proven.SafeUrl.parse(url)
  if parsed.ok {
    Ok(url)
  } else {
    Error(`Invalid URL for ${serviceName}: ${url}`)
  }
}

// =============================================================================
// Config Parsing Helpers
// =============================================================================

let getIntFromJson = (json: JSON.t, default: int): int => {
  switch json->JSON.Classify.classify {
  | Number(n) => n->Float.toInt
  | _ => default
  }
}

let getStringFromJson = (json: JSON.t): option<string> => {
  switch json->JSON.Classify.classify {
  | String(s) => Some(s)
  | _ => None
  }
}

let parseHttpConfig = (raw: Dict.t<JSON.t>): httpConfig => {
  let httpRaw = switch raw->Dict.get("http") {
  | Some(json) =>
    switch json->JSON.Classify.classify {
    | Object(d) => d
    | _ => Dict.make()
    }
  | None => Dict.make()
  }

  {
    timeoutMs: switch httpRaw->Dict.get("timeout_ms") {
    | Some(v) => getIntFromJson(v, defaultHttpConfig.timeoutMs)
    | None => defaultHttpConfig.timeoutMs
    },
    retries: switch httpRaw->Dict.get("retries") {
    | Some(v) => getIntFromJson(v, defaultHttpConfig.retries)
    | None => defaultHttpConfig.retries
    },
    backoffMs: switch httpRaw->Dict.get("backoff_ms") {
    | Some(v) => getIntFromJson(v, defaultHttpConfig.backoffMs)
    | None => defaultHttpConfig.backoffMs
    },
  }
}

let parseServiceConfig = (raw: Dict.t<JSON.t>, key: string, defaultPort: int): result<
  serviceConfig,
> => {
  let svcRaw = switch raw->Dict.get(key) {
  | Some(json) =>
    switch json->JSON.Classify.classify {
    | Object(d) => d
    | _ => Dict.make()
    }
  | None => Dict.make()
  }

  let rawUrl = switch svcRaw->Dict.get("base_url") {
  | Some(v) => getStringFromJson(v)->Option.getOr(`http://127.0.0.1:${defaultPort->Int.toString}`)
  | None => `http://127.0.0.1:${defaultPort->Int.toString}`
  }

  switch validateServiceUrl(rawUrl, key) {
  | Ok(url) =>
    Ok({
      baseUrl: url,
      token: switch svcRaw->Dict.get("token") {
      | Some(v) => getStringFromJson(v)
      | None => None
      },
    })
  | Error(e) => Error(e)
  }
}

// =============================================================================
// File Operations
// =============================================================================

let fileExists = async (path: string): bool => {
  try {
    let _ = await Deno.stat(path)
    true
  } catch {
  | _ => false
  }
}

// =============================================================================
// Config Loading
// =============================================================================

let loadConfigFrom = async (path: string): result<opsmConfig> => {
  try {
    let data = await Deno.readTextFile(path)
    let raw = Toml.parse(data)

    let http = parseHttpConfig(raw)

    let claimForge = switch parseServiceConfig(raw, "claim_forge", 7001) {
    | Ok(c) => c
    | Error(e) => // Can't return early in ReScript, so we'll use a default and check later
      throw(JsError.throwWithMessage(e))
    }

    let checkyMonkey = switch parseServiceConfig(raw, "checky_monkey", 7002) {
    | Ok(c) => c
    | Error(e) => throw(JsError.throwWithMessage(e))
    }

    let palimpsestLicense = switch parseServiceConfig(raw, "palimpsest_license", 7003) {
    | Ok(c) => c
    | Error(e) => throw(JsError.throwWithMessage(e))
    }

    let cicdHyperA = switch parseServiceConfig(raw, "cicd_hyper_a", 7004) {
    | Ok(c) => c
    | Error(e) => throw(JsError.throwWithMessage(e))
    }

    let oikos = switch parseServiceConfig(raw, "oikos", 7005) {
    | Ok(c) => c
    | Error(e) => throw(JsError.throwWithMessage(e))
    }

    Ok({
      http,
      claimForge,
      checkyMonkey,
      palimpsestLicense,
      cicdHyperA,
      oikos,
    })
  } catch {
  | JsExn(e) => Error(JsExn.message(e)->Option.getOr("Failed to load config"))
  }
}

let loadConfig = async (): result<opsmConfig> => {
  // 1. Check OPSM_CONFIG env var
  switch Deno.Env.get("OPSM_CONFIG") {
  | Some(envPath) => await loadConfigFrom(envPath)
  | None => {
      // 2. Check ./opsm.toml
      let localPath = "opsm.toml"
      let localExists = await fileExists(localPath)
      if localExists {
        await loadConfigFrom(localPath)
      } else {
        // 3. Check ~/.config/opsm/opsm.toml
        switch Deno.Env.get("HOME") {
        | Some(home) => {
            let userPath = Path.join([home, ".config", "opsm", "opsm.toml"])
            let userExists = await fileExists(userPath)
            if userExists {
              await loadConfigFrom(userPath)
            } else {
              Error("opsm config not found")
            }
          }
        | None => Error("opsm config not found")
        }
      }
    }
  }
}

let loadConfigOrExample = async (): opsmConfig => {
  switch await loadConfig() {
  | Ok(config) => config
  | Error(_) => exampleConfig()
  }
}
