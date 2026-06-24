// SPDX-License-Identifier: MPL-2.0
// Tauri FFI layer for OPSM Mobile - ReScript bindings for OPSM backend commands

open RescriptCore
open Tauri_Command

// =============================================================================
// Types
// =============================================================================

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

// =============================================================================
// JSON Decoders
// =============================================================================

let decodePackage = (json: JSON.t): result<package, string> => {
  open Tea.Json

  let decoder = map6(
    (name, version, registry, description, license, homepage) => {
      {
        name,
        version,
        registry,
        description,
        license,
        homepage,
      }
    },
    field("name", string),
    field("version", string),
    field("registry", string),
    optional(field("description", string)),
    optional(field("license", string)),
    optional(field("homepage", string)),
  )

  switch decodeValue(decoder, json) {
  | Ok(pkg) => Ok(pkg)
  | Error(err) => Error(Tea.Json.errorToString(err))
  }
}

let decodePackageArray = (json: JSON.t): result<array<package>, string> => {
  open Tea.Json

  let decoder = array(map6(
    (name, version, registry, description, license, homepage) => {
      {
        name,
        version,
        registry,
        description,
        license,
        homepage,
      }
    },
    field("name", string),
    field("version", string),
    field("registry", string),
    optional(field("description", string)),
    optional(field("license", string)),
    optional(field("homepage", string)),
  ))

  switch decodeValue(decoder, json) {
  | Ok(packages) => Ok(packages)
  | Error(err) => Error(Tea.Json.errorToString(err))
  }
}

let decodeSearchResult = (json: JSON.t): result<searchResult, string> => {
  open Tea.Json

  let decoder = map2(
    (packages, total) => {packages, total},
    field("packages", array(map6(
      (name, version, registry, description, license, homepage) => {
        {
          name,
          version,
          registry,
          description,
          license,
          homepage,
        }
      },
      field("name", string),
      field("version", string),
      field("registry", string),
      optional(field("description", string)),
      optional(field("license", string)),
      optional(field("homepage", string)),
    ))),
    field("total", int),
  )

  switch decodeValue(decoder, json) {
  | Ok(result) => Ok(result)
  | Error(err) => Error(Tea.Json.errorToString(err))
  }
}

// =============================================================================
// Command Definitions
// =============================================================================

// Search packages command
let searchCommand = defineCommand(
  ~name="search_packages",
  ~encode=((query, registry)) => {
    Dict.fromArray([
      ("query", JSON.Encode.string(query)),
      ("registry", JSON.Encode.string(registry)),
    ])->Obj.magic
  },
  ~decode=decodeSearchResult,
)

// Get package info command
let getPackageInfoCommand = defineCommand(
  ~name="get_package_info",
  ~encode=((name, version)) => {
    Dict.fromArray([
      ("name", JSON.Encode.string(name)),
      ("version", JSON.Encode.string(version)),
    ])->Obj.magic
  },
  ~decode=decodePackage,
)

// Install package command
let installPackageCommand = defineCommand(
  ~name="install_package",
  ~encode=((registry, name, version)) => {
    Dict.fromArray([
      ("registry", JSON.Encode.string(registry)),
      ("name", JSON.Encode.string(name)),
      ("version", JSON.Encode.string(version)),
    ])->Obj.magic
  },
  ~decode=_ => Ok(), // Void command
)

// List installed packages command
let listInstalledCommand = defineNoArgsCommand(
  ~name="list_installed",
  ~decode=decodePackageArray,
)

// Audit lockfile command
let auditLockfileCommand = defineCommand(
  ~name="audit_lockfile",
  ~encode=path => {
    Dict.fromArray([
      ("path", JSON.Encode.string(path)),
    ])->Obj.magic
  },
  ~decode=json => {
    // Return audit result as JSON
    Ok(json)
  },
)

// =============================================================================
// TEA Command Wrappers
// =============================================================================

// Search packages with TEA Cmd
let searchPackages = (query: string, registry: string, toMsg): Tea.Cmd.t<'msg> => {
  Tea.Cmd.call(callbacks => {
    let _ = execute(searchCommand, (query, registry))
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
}

// Get package info with TEA Cmd
let getPackageInfo = (name: string, version: string, toMsg): Tea.Cmd.t<'msg> => {
  Tea.Cmd.call(callbacks => {
    let _ = execute(getPackageInfoCommand, (name, version))
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
}

// Install package with TEA Cmd
let installPackage = (
  registry: string,
  name: string,
  version: string,
  toMsg,
): Tea.Cmd.t<'msg> => {
  Tea.Cmd.call(callbacks => {
    let _ = execute(installPackageCommand, (registry, name, version))
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
}

// List installed packages with TEA Cmd
let listInstalled = (toMsg): Tea.Cmd.t<'msg> => {
  Tea.Cmd.call(callbacks => {
    let _ = execute(listInstalledCommand, ())
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
}

// Audit lockfile with TEA Cmd
let auditLockfile = (path: string, toMsg): Tea.Cmd.t<'msg> => {
  Tea.Cmd.call(callbacks => {
    let _ = execute(auditLockfileCommand, path)
      ->Promise.thenResolve(result => callbacks.enqueue(toMsg(result)))
  })
}
