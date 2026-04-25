// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// OpsmCommands — OPSM IPC command layer backed by Gossamer via RuntimeBridge.
//
// All commands invoke the Elixir OPSM backend through the Gossamer panel IPC
// (`window.__gossamer_invoke`). In development without Gossamer running the
// browser-HTTP fallback in RuntimeBridge hits the backend directly at
// http://localhost:4051/api.

open Tea
open RescriptCore

// ---------------------------------------------------------------------------
// IPC error type
// ---------------------------------------------------------------------------

type ipcError = string

module IpcError = {
  let toString = (e: ipcError): string => e
}

// ---------------------------------------------------------------------------
// Domain types
// ---------------------------------------------------------------------------

type package = {
  name: string,
  version: string,
  registry: string,
  description: option<string>,
  license: option<string>,
  homepage: option<string>,
}

type installStatus =
  | NotStarted
  | Installing
  | Installed
  | Failed(string)

type searchResult = {
  packages: array<package>,
  total: int,
}

// ---------------------------------------------------------------------------
// JSON decoding
// ---------------------------------------------------------------------------

let decodePackage = (json: JSON.t): result<package, ipcError> => {
  try {
    let obj = json->Obj.magic
    Ok({
      name: obj["name"],
      version: obj["version"],
      registry: obj["registry"],
      description: obj["description"],
      license: obj["license"],
      homepage: obj["homepage"],
    })
  } catch {
  | _ => Error("Failed to decode package")
  }
}

let decodePackageArray = (json: JSON.t): result<array<package>, ipcError> => {
  try {
    let arr: array<JSON.t> = json->Obj.magic
    let pkgs = arr->Array.map(decodePackage)
    if pkgs->Array.some(r => switch r { | Error(_) => true | _ => false }) {
      Error("One or more packages failed to decode")
    } else {
      Ok(pkgs->Array.filterMap(r => switch r { | Ok(p) => Some(p) | _ => None }))
    }
  } catch {
  | _ => Error("Failed to decode package array")
  }
}

let decodeSearchResult = (json: JSON.t): result<searchResult, ipcError> => {
  try {
    let obj = json->Obj.magic
    switch decodePackageArray(obj["packages"]) {
    | Ok(packages) => Ok({packages, total: obj["total"]})
    | Error(e) => Error(e)
    }
  } catch {
  | _ => Error("Failed to decode search result")
  }
}

// ---------------------------------------------------------------------------
// Generic IPC command wrapper
// ---------------------------------------------------------------------------

let invokeCmd = (cmd, args, decode, toMsg): Cmd.t<'msg> => {
  Cmd.call(callbacks => {
    let _ =
      RuntimeBridge.invoke(cmd, args)
      ->Promise.thenResolve(json =>
        switch decode(json) {
        | Ok(value) => callbacks.enqueue(toMsg(Ok(value)))
        | Error(msg) => callbacks.enqueue(toMsg(Error(msg)))
        }
      )
      ->Promise.catch(exn => {
        let msg = switch Js.Exn.asJsExn(exn) {
        | Some(e) => Js.Exn.message(e)->Option.getOr("Unknown IPC error")
        | None => "Unknown IPC error"
        }
        callbacks.enqueue(toMsg(Error(msg)))
        Promise.resolve()
      })
  })
}

// ---------------------------------------------------------------------------
// Package management commands
// ---------------------------------------------------------------------------

let searchPackages = (query: string, registry: string, toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "search_packages",
    {"query": query, "registry": registry},
    decodeSearchResult,
    toMsg,
  )

let getPackageInfo = (name: string, version: string, toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "get_package_info",
    {"name": name, "version": version},
    decodePackage,
    toMsg,
  )

let installPackage = (registry: string, name: string, version: string, toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "install_package",
    {"registry": registry, "name": name, "version": version},
    _ => Ok(),
    toMsg,
  )

let listInstalled = (toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "list_installed",
    Obj.magic(Dict.make()),
    decodePackageArray,
    toMsg,
  )

let auditLockfile = (path: string, toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "audit_lockfile",
    {"path": path},
    json => Ok(json),
    toMsg,
  )

// ---------------------------------------------------------------------------
// Runtime management commands (opsm CLI → Gossamer backend)
// ---------------------------------------------------------------------------

type cliResponse = {
  success: bool,
  output: string,
  exitCode: int,
}

let decodeCliResponse = (json: JSON.t): result<cliResponse, ipcError> => {
  try {
    let obj = json->Obj.magic
    Ok({
      success: obj["success"],
      output: obj["output"],
      exitCode: obj["exit_code"],
    })
  } catch {
  | _ => Error("Failed to decode CLI response")
  }
}

let runtimeList = (toMsg): Cmd.t<'msg> =>
  invokeCmd("opsm_runtime", {"cmd": "list"}, decodeCliResponse, toMsg)

let runtimeInstall = (tool: string, version: option<string>, toMsg): Cmd.t<'msg> =>
  invokeCmd(
    "opsm_runtime",
    {"cmd": "install", "tool": tool, "version": version->Option.getOr("")},
    decodeCliResponse,
    toMsg,
  )

let runtimeRemove = (tool: string, toMsg): Cmd.t<'msg> =>
  invokeCmd("opsm_runtime", {"cmd": "remove", "tool": tool}, decodeCliResponse, toMsg)

let runtimeSearch = (query: string, toMsg): Cmd.t<'msg> =>
  invokeCmd("opsm_runtime", {"cmd": "search", "tool": query}, decodeCliResponse, toMsg)

let healthCheck = (toMsg): Cmd.t<'msg> =>
  invokeCmd("health_check", Obj.magic(Dict.make()), json => Ok(json), toMsg)
