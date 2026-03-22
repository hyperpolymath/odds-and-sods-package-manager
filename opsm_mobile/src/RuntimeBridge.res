// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

/// RuntimeBridge — Unified IPC bridge for OPSM Mobile.
///
/// Detects the available runtime (Gossamer, Tauri, or browser-only) and
/// dispatches `invoke` calls to the appropriate backend. This allows all
/// command modules to use a single import instead of binding directly
/// to `@tauri-apps/api/core`.
///
/// Priority order:
///   1. Gossamer (`window.__gossamer_invoke`)  — own stack, preferred
///   2. Tauri    (`window.__TAURI_INTERNALS__`) — legacy, transition
///   3. Browser  (direct HTTP fetch)            — development fallback

// ---------------------------------------------------------------------------
// Raw external bindings
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

%%raw(`
function isTauriRuntime() {
  return typeof window !== 'undefined'
    && window.__TAURI_INTERNALS__ != null
    && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__;
}
`)
@val external isTauriRuntime: unit => bool = "isTauriRuntime"

@module("@tauri-apps/api/core")
external tauriInvoke: (string, 'a) => promise<'b> = "invoke"

// ---------------------------------------------------------------------------
// Runtime detection
// ---------------------------------------------------------------------------

type runtime =
  | Gossamer
  | Tauri
  | BrowserOnly

%%raw(`
var _detectedRuntime = null;
function detectRuntime() {
  if (_detectedRuntime !== null) return _detectedRuntime;
  if (typeof window !== 'undefined' && typeof window.__gossamer_invoke === 'function') {
    _detectedRuntime = 'gossamer';
  } else if (typeof window !== 'undefined' && window.__TAURI_INTERNALS__ != null && !window.__TAURI_INTERNALS__.__BROWSER_SHIM__) {
    _detectedRuntime = 'tauri';
  } else {
    _detectedRuntime = 'browser';
  }
  return _detectedRuntime;
}
`)
@val external detectRuntimeRaw: unit => string = "detectRuntime"

let detectRuntime = (): runtime => {
  switch detectRuntimeRaw() {
  | "gossamer" => Gossamer
  | "tauri" => Tauri
  | _ => BrowserOnly
  }
}

// ---------------------------------------------------------------------------
// Unified invoke
// ---------------------------------------------------------------------------

/// Invoke a backend command through whatever runtime is available.
let invoke = (cmd: string, args: 'a): promise<'b> => {
  if isGossamerRuntime() {
    gossamerInvoke(cmd, args)
  } else if isTauriRuntime() {
    tauriInvoke(cmd, args)
  } else {
    Promise.reject(
      JsError.throwWithMessage(
        `No desktop runtime — "${cmd}" requires Gossamer or Tauri`,
      ),
    )
  }
}

/// Invoke a command with no arguments.
let invokeSimple = (cmd: string): promise<'a> => {
  invoke(cmd, Obj.magic(Dict.make()))
}

/// Check whether any desktop runtime is available.
let hasDesktopRuntime = (): bool => {
  isGossamerRuntime() || isTauriRuntime()
}

/// Get a human-readable name for the current runtime.
let runtimeName = (): string => {
  switch detectRuntime() {
  | Gossamer => "Gossamer"
  | Tauri => "Tauri"
  | BrowserOnly => "Browser"
  }
}

// ---------------------------------------------------------------------------
// Dialog abstraction
// ---------------------------------------------------------------------------

module Dialog = {
  @module("@tauri-apps/plugin-dialog")
  external tauriOpenRaw: JSON.t => promise<Nullable.t<JSON.t>> = "open"

  @module("@tauri-apps/plugin-dialog")
  external tauriSaveRaw: JSON.t => promise<Nullable.t<JSON.t>> = "save"

  let open = (opts: JSON.t): promise<Nullable.t<JSON.t>> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_dialog_open", opts)
    } else if isTauriRuntime() {
      tauriOpenRaw(opts)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — file dialogs require Gossamer or Tauri",
        ),
      )
    }
  }

  let save = (opts: JSON.t): promise<Nullable.t<JSON.t>> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_dialog_save", opts)
    } else if isTauriRuntime() {
      tauriSaveRaw(opts)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — save dialogs require Gossamer or Tauri",
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Filesystem abstraction
// ---------------------------------------------------------------------------

module Fs = {
  @module("@tauri-apps/plugin-fs")
  external tauriReadTextFileRaw: string => promise<string> = "readTextFile"

  @module("@tauri-apps/plugin-fs")
  external tauriWriteTextFileRaw: (string, string) => promise<unit> = "writeTextFile"

  let readTextFile = (path: string): promise<string> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_fs_read_text", {"path": path})
    } else if isTauriRuntime() {
      tauriReadTextFileRaw(path)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — filesystem access requires Gossamer or Tauri",
        ),
      )
    }
  }

  let writeTextFile = (path: string, contents: string): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_fs_write_text", {"path": path, "contents": contents})
    } else if isTauriRuntime() {
      tauriWriteTextFileRaw(path, contents)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — filesystem access requires Gossamer or Tauri",
        ),
      )
    }
  }
}

// ---------------------------------------------------------------------------
// Event abstraction
// ---------------------------------------------------------------------------

module Event = {
  @module("@tauri-apps/api/event")
  external tauriListen: (string, 'payload => unit) => promise<unit> = "listen"

  @module("@tauri-apps/api/event")
  external tauriEmit: (string, 'payload) => promise<unit> = "emit"

  let listen = (event: string, callback: 'payload => unit): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_listen", {"event": event, "callback": callback})
    } else if isTauriRuntime() {
      tauriListen(event, callback)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event listening requires Gossamer or Tauri",
        ),
      )
    }
  }

  let emit = (event: string, payload: 'payload): promise<unit> => {
    if isGossamerRuntime() {
      gossamerInvoke("__gossamer_event_emit", {"event": event, "payload": payload})
    } else if isTauriRuntime() {
      tauriEmit(event, payload)
    } else {
      Promise.reject(
        JsError.throwWithMessage(
          "No desktop runtime — event emission requires Gossamer or Tauri",
        ),
      )
    }
  }
}
