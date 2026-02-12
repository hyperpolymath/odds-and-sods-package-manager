// SPDX-License-Identifier: PMPL-1.0
@@warning("-44-45")
open Types

// =============================================================================
// Deno FFI Bindings
// =============================================================================

module Deno = {
  type abortController
  type abortSignal
  type response

  @new external makeAbortController: unit => abortController = "AbortController"
  @get external getSignal: abortController => abortSignal = "signal"
  @send external abort: abortController => unit = "abort"

  @val external fetch: (string, {..}) => promise<response> = "fetch"

  @get external responseOk: response => bool = "ok"
  @get external responseStatus: response => int = "status"
  @get external responseStatusText: response => string = "statusText"
  @send external responseText: response => promise<string> = "text"
}

// =============================================================================
// Proven FFI Bindings
// =============================================================================

module Proven = {
  module SafeJson = {
    type parseResult<'a> = {ok: bool, value: option<'a>, error: option<string>}

    @module("@proven/mod.ts") @scope("SafeJson")
    external parse: string => parseResult<JSON.t> = "parse"
  }
}

// =============================================================================
// Helper Functions
// =============================================================================

let sleep = (ms: int): promise<unit> => {
  Promise.make((resolve, _reject) => {
    let _ = setTimeout(() => resolve(), ms)
  })
}

let buildUrl = (baseUrl: string, path: string): string => {
  let trimmedBase = baseUrl->String.replaceRegExp(/\/+$/, "")
  `${trimmedBase}${path}`
}

// =============================================================================
// POST JSON with retries
// =============================================================================

let postJson = async (
  baseUrl: string,
  path: string,
  token: option<string>,
  body: string,
  opts: httpOptions,
): result<unit> => {
  let url = buildUrl(baseUrl, path)
  let attempts = opts.retries + 1

  let headers = Dict.make()
  headers->Dict.set("Content-Type", "application/json")
  switch token {
  | Some(t) => headers->Dict.set("Authorization", `Bearer ${t}`)
  | None => ()
  }

  let lastError = ref("Request failed")
  let success = ref(false)

  for attempt in 0 to attempts - 1 {
    if !success.contents {
      try {
        let controller = Deno.makeAbortController()
        let timeoutId = setTimeout(() => controller->Deno.abort, opts.timeoutMs)

        let response = await Deno.fetch(
          url,
          {
            "method": "POST",
            "headers": Obj.magic(headers),
            "body": body,
            "signal": controller->Deno.getSignal,
          },
        )

        clearTimeout(timeoutId)

        if response->Deno.responseOk {
          success := true
        } else {
          lastError :=
            `HTTP error: ${response
              ->Deno.responseStatus
              ->Int.toString} ${response->Deno.responseStatusText}`

          if attempt + 1 < attempts {
            await sleep(opts.backoffMs * (attempt + 1))
          }
        }
      } catch {
      | JsExn(e) => {
          lastError := JsExn.message(e)->Option.getOr("Unknown error")
          if attempt + 1 < attempts {
            await sleep(opts.backoffMs * (attempt + 1))
          }
        }
      }
    }
  }

  if success.contents {
    Ok()
  } else {
    Error(lastError.contents)
  }
}

// =============================================================================
// GET JSON with retries
// =============================================================================

let getJson = async (
  baseUrl: string,
  path: string,
  token: option<string>,
  opts: httpOptions,
): result<JSON.t> => {
  let url = buildUrl(baseUrl, path)
  let attempts = opts.retries + 1

  let headers = Dict.make()
  headers->Dict.set("Accept", "application/json")
  switch token {
  | Some(t) => headers->Dict.set("Authorization", `Bearer ${t}`)
  | None => ()
  }

  let lastError = ref("Request failed")
  let result = ref(None)

  for attempt in 0 to attempts - 1 {
    if result.contents->Option.isNone {
      try {
        let controller = Deno.makeAbortController()
        let timeoutId = setTimeout(() => controller->Deno.abort, opts.timeoutMs)

        let response = await Deno.fetch(
          url,
          {
            "method": "GET",
            "headers": Obj.magic(headers),
            "signal": controller->Deno.getSignal,
          },
        )

        clearTimeout(timeoutId)

        if response->Deno.responseOk {
          let text = await response->Deno.responseText
          let parsed = Proven.SafeJson.parse(text)
          if parsed.ok {
            switch parsed.value {
            | Some(v) => result := Some(Ok(v))
            | None => result := Some(Error("JSON parse returned null"))
            }
          } else {
            result := Some(Error(`JSON parse error: ${parsed.error->Option.getOr("unknown")}`))
          }
        } else {
          lastError :=
            `HTTP error: ${response
              ->Deno.responseStatus
              ->Int.toString} ${response->Deno.responseStatusText}`

          if attempt + 1 < attempts {
            await sleep(opts.backoffMs * (attempt + 1))
          }
        }
      } catch {
      | JsExn(e) => {
          lastError := JsExn.message(e)->Option.getOr("Unknown error")
          if attempt + 1 < attempts {
            await sleep(opts.backoffMs * (attempt + 1))
          }
        }
      }
    }
  }

  switch result.contents {
  | Some(r) => r
  | None => Error(lastError.contents)
  }
}
