// SPDX-License-Identifier: MPL-2.0
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
// Service Health Type
// =============================================================================

type serviceHealth = {
  status: serviceStatus,
  version: string,
  activeJobs: int,
  queueLength: int,
}

// =============================================================================
// JSON Encoding
// =============================================================================

let encodeVerificationType = (t: verificationType): string => {
  switch t {
  | PropertyTests => "property-tests"
  | FuzzTesting => "fuzz-testing"
  | TypeChecking => "type-checking"
  | FormalVerification => "formal-verification"
  | MutationTesting => "mutation-testing"
  }
}

let decodeVerificationType = (s: string): verificationType => {
  switch s {
  | "property-tests" => PropertyTests
  | "fuzz-testing" => FuzzTesting
  | "type-checking" => TypeChecking
  | "formal-verification" => FormalVerification
  | "mutation-testing" => MutationTesting
  | _ => PropertyTests
  }
}

let encodeVerificationRequest = (req: checkyMonkeyRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("repositoryUrl", req.repositoryUrl->JSON.Encode.string)
  obj->Dict.set("commitSha", req.commitSha->JSON.Encode.string)
  obj->Dict.set(
    "verificationTypes",
    req.verificationTypes
    ->Array.map(t => t->encodeVerificationType->JSON.Encode.string)
    ->JSON.Encode.array,
  )
  switch req.timeout {
  | Some(t) => obj->Dict.set("timeout", t->Int.toFloat->JSON.Encode.float)
  | None => ()
  }
  obj->JSON.Encode.object->JSON.stringify
}

// =============================================================================
// Response Decoding
// =============================================================================

let decodeVerificationStatus = (s: string): verificationStatus => {
  switch s {
  | "queued" => Queued
  | "running" => Running
  | "completed" => Completed
  | "failed" => Failed
  | _ => Failed
  }
}

// =============================================================================
// API Methods
// =============================================================================

let submitVerification = async (client: t, request: checkyMonkeyRequest): result<
  checkyMonkeyResponse,
> => {
  let body = encodeVerificationRequest(request)

  switch await Http.postJson(client.baseUrl, "/verify", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let sha = request.commitSha->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/verify/status/${sha}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(_json) =>
        Ok({
          requestId: sha,
          status: Queued,
          startedAt: None,
          completedAt: None,
          results: None,
        })
      }
    }
  }
}

let getStatus = async (client: t, requestId: string): result<checkyMonkeyResponse> => {
  let path = `/verify/${requestId->encodeURIComponent}`

  switch await Http.getJson(client.baseUrl, path, client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      requestId,
      status: Queued,
      startedAt: None,
      completedAt: None,
      results: None,
    })
  }
}

let listVerificationTypes = async (client: t): result<array<verificationType>> => {
  switch await Http.getJson(client.baseUrl, "/verification-types", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) => Ok([PropertyTests, FuzzTesting, TypeChecking, FormalVerification, MutationTesting])
  }
}

let cancel = async (client: t, requestId: string): result<unit> => {
  let path = `/verify/${requestId->encodeURIComponent}/cancel`

  switch await Http.postJson(client.baseUrl, path, client.token, "{}", client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => Ok()
  }
}

let health = async (client: t): result<serviceHealth> => {
  switch await Http.getJson(client.baseUrl, "/health", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(_json) =>
    Ok({
      status: Healthy,
      version: "unknown",
      activeJobs: 0,
      queueLength: 0,
    })
  }
}
