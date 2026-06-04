<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Implementation phasing

## Phase 0 — definition and schema
- freeze canonical brief
- define core entities and enums
- define policy/capability schema
- define provenance model

## Phase 1 — planner and canonical model
- build VeriSim-backed model
- build source federation layer
- implement ActionPlan generation
- implement target and profile recommendation
- implement trust/reversibility evaluation

## Phase 2 — install/configure core
- integrate package backends
- integrate JanusKey reversible kernel
- implement install/configure flow
- checkpoints and rollback
- essential environment wiring
- essential local service enablement
- essential secrets handling

## Phase 3 — analysis and safer execution
- Panic Attack on-download integration
- Panic Attack on-run integration
- watched/neutered/containerised/VM downgrade paths
- community/reputation signal integration

## Phase 4 — front end and explanation
- CLI/TUI refinement
- PanLL panel integration
- dashboard with contextual wizards
- trust/reversibility always-visible overlays
- package and plan detail views

## Phase 5 — ecosystem uplift
- Feedback-o-Tron integration
- generated templates for maintainers
- telemetry options
- reviewed upstream feedback submission
