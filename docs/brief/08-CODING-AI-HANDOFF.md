<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Coding AI handoff brief

Treat `00-MASTER-BRIEF.md` as the primary source of truth.

## Core instruction

Build OPSM as a federated package manager with integrated configuration and target-aware placement. The system must discover, compare, plan, install, configure, and perform essential local environment wiring, essential local service enablement, and essential secrets setup. It must treat source, target, lifecycle, execution mode, install profile, architecture, trust, and reversibility as first-class concerns.

## Key constraints

- Use VeriSim as the canonical internal store.
- Use federation around VeriSim, not in place of it.
- Use JanusKey/Bennett-style logic as the reversible kernel for state mutation and recovery.
- Integrate Panic Attack as a first-class analysis engine for on-download and on-run assessment.
- Preserve provenance for extracted instructions.
- Distinguish upstream instructions, OPSM-normalized steps, backend-native steps, and user-authored steps.
- Prefer the safest overall recommendation strategy, with reversibility heavily weighted and always visible.
- Use risk-adaptive downgrade paths instead of simple allow/block wherever possible.
- Keep package management at the public centre, with configuration in the core and provisioning deferred upward.

## V1 boundaries

Do:
- local and narrow cloud targets
- local software-defined target creation where practical
- package management + configuration
- strict trust and reversibility treatment

Do not expand into:
- full organisational identity integration
- enterprise policy/directory integration
- remote fleet management
- general remote-machine orchestration
- full cloud control-plane management

## Architectural preference

Many ways in, one model underneath.

Use:
- a2ml / k9 as canonical structured layer
- Nickel as major companion
- import/export and compatibility via YAML/TOML/JSON through Nickel
- shell/just/Ansible/Terraform/Containerfiles/systemd as execution/integration layer

## Important non-goal for the model

Do not redesign the system around one narrow host model such as immutable Fedora alone. Treat host, isolated local targets, media targets, device/peripheral targets, and narrow cloud targets as first-class families.
