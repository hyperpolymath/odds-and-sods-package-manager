-- SPDX-License-Identifier: PMPL-1.0-or-later
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Types.idr — Core types for the Bennett reversible uninstall ABI.
--
-- Models the system state and install/uninstall actions that OPSM performs.
-- Each Action has a well-defined inverse (ReverseAction), following
-- Bennett's reversible computation principle: every forward step can be
-- exactly undone, returning the system to its prior state.

module Types

import Data.List

%default total

||| A filesystem path, represented as a list of path components.
||| Using a list rather than a raw String gives us structural equality
||| which is essential for the proofs.
public export
Path : Type
Path = List String

||| File permission mode (simplified to a natural number).
public export
PermissionMode : Type
PermissionMode = Nat

||| An environment variable binding: name and value.
public export
record EnvBinding where
  constructor MkEnvBinding
  envName  : String
  envValue : String

||| Desktop entry metadata for .desktop file registration.
public export
record DesktopEntry where
  constructor MkDesktopEntry
  appName     : String
  execPath    : Path
  iconPath    : Path
  categories  : List String

||| A systemd unit descriptor.
public export
record SystemdUnit where
  constructor MkSystemdUnit
  unitName : String
  unitType : String  -- "service", "timer", "socket"

||| File content, modelled abstractly as a natural number tag.
||| We do not model raw bytes; what matters for reversibility is that
||| content is preserved across round-trips.
public export
FileContent : Type
FileContent = Nat

||| An install action — one atomic step that OPSM performs when
||| installing a package. Each constructor mirrors an operation in
||| Opsm.Package.Installer and Opsm.Package.Cleanup.
public export
data Action : Type where
  ||| Create a file with given content at the specified path.
  CreateFile      : (path : Path) -> (content : FileContent) -> Action
  ||| Create a directory at the specified path.
  CreateDir       : (path : Path) -> Action
  ||| Set permission mode on a path (old mode recorded for reversal).
  SetPermission   : (path : Path) -> (oldMode : PermissionMode) -> (newMode : PermissionMode) -> Action
  ||| Register a .desktop file for desktop integration.
  RegisterDesktop : (entry : DesktopEntry) -> Action
  ||| Add an environment variable binding.
  AddEnvVar       : (binding : EnvBinding) -> Action
  ||| Enable a systemd user unit.
  EnableSystemd   : (unit : SystemdUnit) -> Action
  ||| Register a MIME type association.
  RegisterMime    : (packageName : String) -> (mimeXml : FileContent) -> Action
  ||| Create an autostart entry.
  AddAutostart    : (packageName : String) -> Action

||| The reverse of an install action. Each constructor undoes exactly
||| one Action constructor.
public export
data ReverseAction : Type where
  ||| Remove a file that was created.
  RemoveFile        : (path : Path) -> (content : FileContent) -> ReverseAction
  ||| Remove a directory that was created.
  RemoveDir         : (path : Path) -> ReverseAction
  ||| Restore the old permission mode.
  RestorePermission : (path : Path) -> (oldMode : PermissionMode) -> (newMode : PermissionMode) -> ReverseAction
  ||| Unregister a .desktop file.
  UnregisterDesktop : (entry : DesktopEntry) -> ReverseAction
  ||| Remove an environment variable.
  RemoveEnvVar      : (binding : EnvBinding) -> ReverseAction
  ||| Disable a systemd unit.
  DisableSystemd    : (unit : SystemdUnit) -> ReverseAction
  ||| Unregister a MIME type.
  UnregisterMime    : (packageName : String) -> (mimeXml : FileContent) -> ReverseAction
  ||| Remove an autostart entry.
  RemoveAutostart   : (packageName : String) -> ReverseAction

||| Compute the reverse of an action. This is a pure, total function
||| — every action has exactly one inverse.
public export
reverse : Action -> ReverseAction
reverse (CreateFile p c)        = RemoveFile p c
reverse (CreateDir p)           = RemoveDir p
reverse (SetPermission p o n)   = RestorePermission p o n
reverse (RegisterDesktop e)     = UnregisterDesktop e
reverse (AddEnvVar b)           = RemoveEnvVar b
reverse (EnableSystemd u)       = DisableSystemd u
reverse (RegisterMime pkg xml)  = UnregisterMime pkg xml
reverse (AddAutostart pkg)      = RemoveAutostart pkg

||| A sequence of install actions, applied in order.
public export
ActionSequence : Type
ActionSequence = List Action

||| Compute the reverse of an entire action sequence.
||| Per Bennett's principle, the reverse sequence is the original
||| sequence reversed and each action individually reversed.
public export
reverseSequence : ActionSequence -> List ReverseAction
reverseSequence actions = map reverse (reverse actions)
