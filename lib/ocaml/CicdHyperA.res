// SPDX-License-Identifier: PMPL-1.0
@@warning("-44-45")
open Types

// =============================================================================
// Client Type
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
// Validation Types
// =============================================================================

type validationError = {
  ruleId: string,
  rulesetId: string,
  message: string,
  path: option<string>,
}

type validationWarning = {
  ruleId: string,
  rulesetId: string,
  message: string,
  path: option<string>,
}

type validationResult = {
  valid: bool,
  errors: array<validationError>,
  warnings: array<validationWarning>,
}

type federationStatusResponse = {
  packageName: string,
  version: string,
  syncedAt: string,
  targets: Dict.t<syncState>,
}

// =============================================================================
// JSON Encoding
// =============================================================================

let encodeAttestationType = (t: attestationType): string => {
  switch t {
  | ClaimForge => "claim-forge"
  | Sigstore => "sigstore"
  | InToto => "in-toto"
  }
}

let encodeAttestationRef = (ref: attestationRef): Dict.t<JSON.t> => {
  let obj = Dict.make()
  obj->Dict.set("type", ref.attestationType->encodeAttestationType->JSON.Encode.string)
  obj->Dict.set("uri", ref.uri->JSON.Encode.string)
  obj->Dict.set("digest", ref.digest->JSON.Encode.string)
  obj
}

let encodePackageMetadata = (m: packageMetadata): Dict.t<JSON.t> => {
  let obj = Dict.make()
  obj->Dict.set("name", m.name->JSON.Encode.string)
  obj->Dict.set("version", m.version->JSON.Encode.string)
  switch m.description {
  | Some(d) => obj->Dict.set("description", d->JSON.Encode.string)
  | None => ()
  }
  obj->Dict.set("license", m.license->JSON.Encode.string)
  switch m.repository {
  | Some(r) => obj->Dict.set("repository", r->JSON.Encode.string)
  | None => ()
  }
  obj->Dict.set("authors", m.authors->Array.map(JSON.Encode.string)->JSON.Encode.array)
  obj->Dict.set("keywords", m.keywords->Array.map(JSON.Encode.string)->JSON.Encode.array)
  obj
}

let encodePublishRequest = (req: cicdPublishRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("manifest", req.manifest->encodePackageMetadata->JSON.Encode.object)
  switch req.tarballUrl {
  | Some(url) => obj->Dict.set("tarballUrl", url->JSON.Encode.string)
  | None => ()
  }
  obj->Dict.set(
    "attestations",
    req.attestations
    ->Array.map(a => a->encodeAttestationRef->JSON.Encode.object)
    ->JSON.Encode.array,
  )
  obj->JSON.Encode.object->JSON.stringify
}

let encodeQueryRequest = (req: packageQueryRequest): string => {
  let versionPart = switch req.version {
  | Some(v) => `/${v}`
  | None => ""
  }
  let queryParams = switch req.includeScores {
  | Some(true) => "?includeScores=true"
  | _ => ""
  }
  `${req.name->encodeURIComponent}${versionPart}${queryParams}`
}

// =============================================================================
// API Methods
// =============================================================================

let publish = async (client: t, request: cicdPublishRequest): result<cicdPublishResponse> => {
  let body = encodePublishRequest(request)

  switch await Http.postJson(client.baseUrl, "/packages/publish", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let name = request.manifest.name->encodeURIComponent
      let version = request.manifest.version
      switch await Http.getJson(
        client.baseUrl,
        `/packages/${name}/${version}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        // Parse response - simplified for now
        Ok({
          packageId: `${request.manifest.name}@${request.manifest.version}`,
          version: request.manifest.version,
          publishedAt: "",
          registryUrl: `${client.baseUrl}/packages/${name}/${version}`,
          federationStatus: {
            github: {synced: false, lastSync: None, error: None},
            gitlab: {synced: false, lastSync: None, error: None},
            codeberg: {synced: false, lastSync: None, error: None},
            radicle: {synced: false, lastSync: None, error: None},
            ipfs: None,
          },
        })
      }
    }
  }
}

let queryPackage = async (client: t, request: packageQueryRequest): result<
  packageQueryResponse,
> => {
  let path = `/packages/${encodeQueryRequest(request)}`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    // Parse response - simplified for now
    Ok({
      package: {
        name: request.name,
        version: request.version->Option.getOr("0.0.0"),
        description: None,
        license: "PMPL-1.0",
        repository: None,
        authors: [],
        keywords: [],
        dependencies: Dict.make(),
        devDependencies: None,
      },
      versions: [],
      latestVersion: "0.0.0",
      scores: None,
      dependents: 0,
      downloads: 0,
    })
  }
}

let listRulesets = async (client: t): result<array<ruleset>> => {
  switch await Http.getJson(client.baseUrl, "/rulesets", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) => Ok([])
  }
}

let getRuleset = async (client: t, rulesetId: string): result<ruleset> => {
  let path = `/rulesets/${rulesetId->encodeURIComponent}`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      id: rulesetId,
      name: "",
      version: "0.0.0",
      rules: [],
      appliesTo: [],
    })
  }
}

let validateManifest = async (
  client: t,
  manifest: packageMetadata,
  rulesetIds: option<array<string>>,
): result<validationResult> => {
  let obj = Dict.make()
  obj->Dict.set("manifest", manifest->encodePackageMetadata->JSON.Encode.object)
  obj->Dict.set(
    "rulesetIds",
    rulesetIds->Option.getOr(["default"])->Array.map(JSON.Encode.string)->JSON.Encode.array,
  )
  let body = obj->JSON.Encode.object->JSON.stringify

  switch await Http.postJson(client.baseUrl, "/validate", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) =>
    Ok({
      valid: true,
      errors: [],
      warnings: [],
    })
  }
}

let getFederationStatus = async (client: t, packageName: string, version: string): result<
  federationStatusResponse,
> => {
  let path = `/packages/${packageName->encodeURIComponent}/${version}/federation`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      packageName,
      version,
      syncedAt: "",
      targets: Dict.make(),
    })
  }
}
