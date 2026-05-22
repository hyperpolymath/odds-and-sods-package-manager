// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// RuntimeBridge — Gossamer IPC bridge for OPSM Mobile.
//
// Dispatches commands through Gossamer's panel IPC
// (`window.__gossamer_invoke`) with a plain browser-HTTP fallback for
// development mode when Gossamer is not wrapping the page.
//
// Tauri support has been removed (2026-04-25); Gossamer is the sole desktop
// runtime.

open RescriptCore

// ---------------------------------------------------------------------------
// Gossamer IPC
// ---------------------------------------------------------------------------

%%raw(`
function isGossamerRuntime() {
  return typeof window !== 'undefined'
    && typeof window.__gossamer_invoke === 'function';
}
`)
@val external isGossamerRuntime: unit => bool = "isGossamerRuntime"

%%raw(`
function gossamerInvoke(cmd, args) {
  return window.__gossamer_invoke(cmd, args);
}
`)
@val external gossamerInvoke: (string, 'a) => promise<'b> = "gossamerInvoke"

// ---------------------------------------------------------------------------
// Browser-HTTP fallback (development / test without Gossamer running)
// ---------------------------------------------------------------------------

let apiBase = (): string => {
  %raw(`
    (typeof process !== 'undefined' && process.env && process.env.OPSM_API_URL)
      ? process.env.OPSM_API_URL
      : "http://localhost:4051/api"
  `)
}

let browserFetch = (cmd: string, args: 'a): promise<'b> => {
  let body = JSON.stringifyAny(args)->Option.getOr("{}")
  let url = apiBase() ++ "/cmd/" ++ cmd
  Fetch.fetch(
    url,
    {
      method: #POST,
      headers: Fetch.Headers.fromObject({"Content-Type": "application/json"}),
      body: body,
    },
  )
  ->Promise.then(resp => resp->Fetch.Response.json)
  ->Promise.then(json => Promise.resolve(json->Obj.magic))
}

// ---------------------------------------------------------------------------
// Runtime detection
// ---------------------------------------------------------------------------

type runtime =
  | Gossamer
  | BrowserOnly

let detectRuntime = (): runtime =>
  if isGossamerRuntime() { Gossamer } else { BrowserOnly }

let hasDesktopRuntime = (): bool => isGossamerRuntime()

let runtimeName = (): string =>
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | BrowserOnly => "Browser"
  }

// ---------------------------------------------------------------------------
// Unified invoke
// ---------------------------------------------------------------------------

/// Invoke a backend command. Gossamer IPC when available; browser HTTP fetch
/// when running in a plain browser (development / CI preview).
let invoke = (cmd: string, args: 'a): promise<'b> =>
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else {
    browserFetch(cmd, args)
  }

let invokeSimple = (cmd: string): promise<'a> =>
  invoke(cmd, Obj.magic(Dict.make()))

// ---------------------------------------------------------------------------
// Filesystem (Gossamer-only)
// ---------------------------------------------------------------------------

module Fs = {
  let readTextFile = (path: string): promise<string> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_fs_read_text", {"path": path})
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — filesystem access requires Gossamer"),
      )
    }

  let writeTextFile = (path: string, contents: string): promise<unit> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_fs_write_text", {"path": path, "contents": contents})
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — filesystem access requires Gossamer"),
      )
    }
}

// ---------------------------------------------------------------------------
// Dialog (Gossamer-only)
// ---------------------------------------------------------------------------

module Dialog = {
  let open = (opts: JSON.t): promise<Nullable.t<JSON.t>> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_dialog_open", opts)
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — file dialogs require Gossamer"),
      )
    }

  let save = (opts: JSON.t): promise<Nullable.t<JSON.t>> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_dialog_save", opts)
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — save dialogs require Gossamer"),
      )
    }
}

// ---------------------------------------------------------------------------
// Event (Gossamer-only)
// ---------------------------------------------------------------------------

module Event = {
  let listen = (event: string, callback: 'payload => unit): promise<unit> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_listen", {"event": event, "callback": callback})
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — event listening requires Gossamer"),
      )
    }

  let emit = (event: string, payload: 'payload): promise<unit> =>
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_emit", {"event": event, "payload": payload})
    } else {
      Promise.reject(
        JsError.throwWithMessage("No desktop runtime — event emission requires Gossamer"),
      )
    }
}
