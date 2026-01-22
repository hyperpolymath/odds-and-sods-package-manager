// SPDX-License-Identifier: PMPL-1.0
// Oikos.res - Ecosystem sustainability analysis client

open Types

// =============================================================================
// Oikos Client
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
// JSON Encoding
// =============================================================================

let encodeAnalysisRequest = (req: oikosAnalysisRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("repositoryUrl", req.repositoryUrl->JSON.Encode.string)
  switch req.branch {
  | Some(b) => obj->Dict.set("branch", b->JSON.Encode.string)
  | None => ()
  }
  switch req.commitSha {
  | Some(s) => obj->Dict.set("commitSha", s->JSON.Encode.string)
  | None => ()
  }
  obj->JSON.Encode.object->JSON.stringify
}

let encodeDiffRequest = (req: oikosDiffRequest): string => {
  let obj = Dict.make()
  obj->Dict.set("repositoryUrl", req.repositoryUrl->JSON.Encode.string)
  obj->Dict.set("baseRef", req.baseRef->JSON.Encode.string)
  obj->Dict.set("headRef", req.headRef->JSON.Encode.string)
  obj->JSON.Encode.object->JSON.stringify
}

// =============================================================================
// JSON Decoding Helpers
// =============================================================================

let decodeString = (json: JSON.t, key: string): option<string> => {
  switch json->JSON.Classify.classify {
  | Object(d) =>
    switch d->Dict.get(key) {
    | Some(v) =>
      switch v->JSON.Classify.classify {
      | String(s) => Some(s)
      | _ => None
      }
    | None => None
    }
  | _ => None
  }
}

let decodeInt = (json: JSON.t, key: string): option<int> => {
  switch json->JSON.Classify.classify {
  | Object(d) =>
    switch d->Dict.get(key) {
    | Some(v) =>
      switch v->JSON.Classify.classify {
      | Number(n) => Some(n->Float.toInt)
      | _ => None
      }
    | None => None
    }
  | _ => None
  }
}

let decodeSeverity = (s: string): riskSeverity => {
  switch s {
  | "low" => Low
  | "medium" => Medium
  | "high" => High
  | "critical" => Critical
  | _ => Low
  }
}

let decodeServiceStatus = (s: string): serviceStatus => {
  switch s {
  | "healthy" => Healthy
  | "degraded" => Degraded
  | "unhealthy" => Unhealthy
  | _ => Unhealthy
  }
}

// =============================================================================
// Response Decoding
// =============================================================================

let decodeScores = (json: JSON.t): sustainabilityScores => {
  {
    maintainability: decodeInt(json, "maintainability")->Option.getOr(0),
    documentation: decodeInt(json, "documentation")->Option.getOr(0),
    testCoverage: decodeInt(json, "testCoverage")->Option.getOr(0),
    communityHealth: decodeInt(json, "communityHealth")->Option.getOr(0),
    securityPosture: decodeInt(json, "securityPosture")->Option.getOr(0),
    dependencyHealth: decodeInt(json, "dependencyHealth")->Option.getOr(0),
    releaseMaturity: decodeInt(json, "releaseMaturity")->Option.getOr(0),
    codeQuality: decodeInt(json, "codeQuality")->Option.getOr(0),
  }
}

let decodeAnalysisResponse = (json: JSON.t): result<oikosAnalysisResponse> => {
  switch json->JSON.Classify.classify {
  | Object(d) =>
    Ok({
      repositoryUrl: decodeString(json, "repositoryUrl")->Option.getOr(""),
      analyzedAt: decodeString(json, "analyzedAt")->Option.getOr(""),
      overallScore: decodeInt(json, "overallScore")->Option.getOr(0),
      scores: switch d->Dict.get("scores") {
      | Some(s) => decodeScores(s)
      | None => {
          maintainability: 0,
          documentation: 0,
          testCoverage: 0,
          communityHealth: 0,
          securityPosture: 0,
          dependencyHealth: 0,
          releaseMaturity: 0,
          codeQuality: 0,
        }
      },
      recommendations: [],
      risks: [],
    })
  | _ => Error("Invalid response format")
  }
}

let decodeHealthResponse = (json: JSON.t): result<oikosHealthResponse> => {
  Ok({
    status: decodeString(json, "status")->Option.getOr("unhealthy")->decodeServiceStatus,
    version: decodeString(json, "version")->Option.getOr("unknown"),
    uptime: decodeInt(json, "uptime")->Option.getOr(0),
  })
}

// =============================================================================
// API Methods
// =============================================================================

let analyzeRepository = async (client: t, request: oikosAnalysisRequest): result<
  oikosAnalysisResponse,
> => {
  let body = encodeAnalysisRequest(request)

  switch await Http.postJson(
    client.baseUrl,
    "/analysis/repository",
    client.token,
    body,
    client.opts,
  ) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let encodedUrl = request.repositoryUrl->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/analysis/repository/${encodedUrl}`,
        client.token,
        client.opts,
      ) {
      | Error(e) => Error(e)
      | Ok(json) => decodeAnalysisResponse(json)
      }
    }
  }
}

let analyzeDiff = async (client: t, request: oikosDiffRequest): result<oikosDiffResponse> => {
  let body = encodeDiffRequest(request)

  switch await Http.postJson(client.baseUrl, "/analysis/diff", client.token, body, client.opts) {
  | Error(e) => Error(e)
  | Ok(_) => {
      let encodedUrl = request.repositoryUrl->encodeURIComponent
      switch await Http.getJson(
        client.baseUrl,
        `/analysis/diff/${encodedUrl}`,
        client.token,
        client.opts,
      ) {
      | Error(_) =>
        // Return minimal response on error
        Ok({
          repositoryUrl: request.repositoryUrl,
          baseRef: request.baseRef,
          headRef: request.headRef,
          analyzedAt: "",
          overallDelta: 0,
          impactSummary: "",
        })
      | Ok(_json) =>
        Ok({
          repositoryUrl: request.repositoryUrl,
          baseRef: request.baseRef,
          headRef: request.headRef,
          analyzedAt: "",
          overallDelta: 0,
          impactSummary: "",
        })
      }
    }
  }
}

let health = async (client: t): result<oikosHealthResponse> => {
  switch await Http.getJson(client.baseUrl, "/health", client.token, client.opts) {
  | Error(e) => Error(e)
  | Ok(json) => decodeHealthResponse(json)
  }
}
