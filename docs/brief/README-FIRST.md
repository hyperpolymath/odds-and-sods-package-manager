<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# OPSM brief bundle

This bundle is designed to be usable with coding AIs in three ways:

1. **Best for quality**: upload the whole bundle if the AI can read multiple files.
2. **Best for weaker context windows**: paste `00-MASTER-BRIEF.md` first, then add the other files as needed.
3. **Best for staged implementation**: feed files in this order:
   - `00-MASTER-BRIEF.md`
   - `01-VISION.md`
   - `02-ARCHITECTURE.md`
   - `03-V1-SCOPE.md`
   - `04-DATA-MODEL.md`
   - `05-TRUST-REVERSIBILITY.md`
   - `06-PLUGIN-POLICY.md`
   - `07-IMPLEMENTATION-PHASING.md`
   - `08-CODING-AI-HANDOFF.md`

## Practical guidance for coding AIs

- A **single giant paste** is usually worse than a structured bundle unless the model has a very large context window and good retrieval.
- A **single master file plus focused supporting files** is usually the best compromise.
- **Stage delivery** is often best when the model tends to drift: first give purpose and scope, then architecture, then exact implementation constraints.
- Keep **one canonical source of truth**. If you revise anything, revise the master brief and note the change in the architecture or scope files.

## Recommended usage patterns

### If the coding AI supports multi-file upload
Upload the whole ZIP and say:

> Treat `00-MASTER-BRIEF.md` as the primary source of truth. Use the other files as focused supporting documents. Do not invent scope outside v1 unless explicitly marked as deferred or future work.

### If the coding AI only works well with pasted text
Paste in this order:

1. `00-MASTER-BRIEF.md`
2. `03-V1-SCOPE.md`
3. `02-ARCHITECTURE.md`
4. `08-CODING-AI-HANDOFF.md`

Then, only paste the more detailed files if needed.

### If the coding AI loses focus over long sessions
At the start of each new subtask, re-paste:

- the short project identity paragraph from `00-MASTER-BRIEF.md`
- the exact v1 boundary from `03-V1-SCOPE.md`
- the relevant section from `08-CODING-AI-HANDOFF.md`

## Short answer on token/attention handling

It does make a difference.

- **One huge file**: simplest, but easier for the model to blur sections together.
- **Many focused files**: usually better if the AI can browse or retrieve well.
- **Stage delivery**: often best for implementation work because it reduces drift and attention dilution.

The safest pattern is:

- one **master brief**
- several **focused supporting files**
- staged handoff during concrete development
