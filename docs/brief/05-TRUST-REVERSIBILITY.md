<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Trust, attestation, and reversibility

## Trust model

Priority order:
1. signed publisher identity
2. allowlist / registry policy
3. heuristic score with explanation
4. package-manager metadata only as transitional fallback

## Hard trust vs reputation

### Hard trust
- signature presence
- signer identity
- attestation / provenance
- publisher status
- hashes
- policy result

### Reputation / community evidence
- VirusTotal-style analysis
- community comments
- maintainer responsiveness
- ratings
- crowdsourced rules/verdicts
- ecosystem chatter

## Reversibility

Strict across:
- package operations
- configuration
- essential service enablement
- essential secrets-related setup

### JanusKey role
Use JanusKey/Bennett-style reversibility as the reversible kernel for state mutation and recovery.

### Caution
External effects are not automatically reversible just because internal state transitions are.

## Risk downgrade ladder
- normal
- caution
- risky
- dangerous
- forbidden

Safer alternatives:
- minimal
- containerised
- watched
- neutered
- VM
- relay-only
