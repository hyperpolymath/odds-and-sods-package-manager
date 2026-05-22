-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
--
-- Layout.idr — System state model for the Bennett reversible uninstall ABI.
--
-- Defines the abstract system state as a record of observable effects.
-- Each field corresponds to one kind of artifact that install actions
-- create and uninstall actions must remove.
--
-- Design note: apply prepends to the front of each list, and unapply
-- removes from the front. This stack discipline ensures that the
-- reversibility proof reduces by straightforward computation.

module Layout

import Types
import Data.List

%default total

||| Abstract system state. Each field is a list of artifacts currently
||| present. The model is intentionally abstract — we track *what exists*,
||| not the underlying filesystem implementation.
public export
record SystemState where
  constructor MkSystemState
  ||| Files that exist: (path, content) pairs.
  files       : List (Path, FileContent)
  ||| Directories that exist.
  dirs        : List Path
  ||| Permission overrides: (path, oldMode, currentMode) triples.
  permissions : List (Path, PermissionMode, PermissionMode)
  ||| Registered desktop entries.
  desktopEntries : List DesktopEntry
  ||| Active environment variable bindings.
  envVars     : List EnvBinding
  ||| Enabled systemd units.
  systemdUnits : List SystemdUnit
  ||| Registered MIME types: (packageName, xmlContent) pairs.
  mimeTypes   : List (String, FileContent)
  ||| Active autostart entries (by package name).
  autostarts  : List String

||| The empty system state — nothing installed.
public export
emptyState : SystemState
emptyState = MkSystemState [] [] [] [] [] [] [] []

||| Apply a single install action to the system state.
||| Each action pushes exactly one artifact onto the front of the
||| appropriate field (stack discipline).
public export
apply : Action -> SystemState -> SystemState
apply (CreateFile p c) s =
  { files := (p, c) :: s.files } s
apply (CreateDir p) s =
  { dirs := p :: s.dirs } s
apply (SetPermission p o n) s =
  { permissions := (p, o, n) :: s.permissions } s
apply (RegisterDesktop e) s =
  { desktopEntries := e :: s.desktopEntries } s
apply (AddEnvVar b) s =
  { envVars := b :: s.envVars } s
apply (EnableSystemd u) s =
  { systemdUnits := u :: s.systemdUnits } s
apply (RegisterMime pkg xml) s =
  { mimeTypes := (pkg, xml) :: s.mimeTypes } s
apply (AddAutostart pkg) s =
  { autostarts := pkg :: s.autostarts } s

||| Apply a reverse action (unapply) to the system state.
||| Each reverse action pops the head of the appropriate field —
||| the exact artifact that the corresponding forward action pushed.
public export
unapply : ReverseAction -> SystemState -> SystemState
unapply (RemoveFile _ _) s =
  { files := drop 1 s.files } s
unapply (RemoveDir _) s =
  { dirs := drop 1 s.dirs } s
unapply (RestorePermission _ _ _) s =
  { permissions := drop 1 s.permissions } s
unapply (UnregisterDesktop _) s =
  { desktopEntries := drop 1 s.desktopEntries } s
unapply (RemoveEnvVar _) s =
  { envVars := drop 1 s.envVars } s
unapply (DisableSystemd _) s =
  { systemdUnits := drop 1 s.systemdUnits } s
unapply (UnregisterMime _ _) s =
  { mimeTypes := drop 1 s.mimeTypes } s
unapply (RemoveAutostart _) s =
  { autostarts := drop 1 s.autostarts } s

||| Apply a sequence of actions left-to-right.
public export
applySequence : ActionSequence -> SystemState -> SystemState
applySequence []        s = s
applySequence (a :: as) s = applySequence as (apply a s)

||| Apply a sequence of reverse actions left-to-right.
public export
unapplySequence : List ReverseAction -> SystemState -> SystemState
unapplySequence []        s = s
unapplySequence (r :: rs) s = unapplySequence rs (unapply r s)
