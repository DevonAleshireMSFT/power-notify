---
adr: 0007
title: Schema as source, via manifests
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0007 — Schema as source, via manifests


## Context

Power Notify's data model is roughly 126 columns, 20 relationships, 7 alternate keys, and 13 global
choices across 11 tables. Two authoring approaches were available:

1. Click each component in the maker portal, then export and unpack.
2. Author the unpacked solution XML directly and import it.

Hand-clicking does not produce a reviewable diff and is slow to repeat across environments. Raw
Dataverse attribute XML is roughly forty lines per column — several thousand lines that no one will
review meaningfully.

## Decision

Declare schema in compact CSV manifests and expand them into solution XML with a generator:

| Manifest | Declares |
|---|---|
| `schema/pnfy-columns.csv` | Every non-lookup column |
| `schema/pnfy-relationships.csv` | Every lookup plus its cascade behaviour |
| `schema/pnfy-keys.csv` | Alternate keys and their column sets |
| `schema/pnfy-secured-columns.csv` | Columns requiring column security |

`build/Build-PnfySchema.ps1` expands these into the unpacked solution source. The exported solution
XML remains the source of truth; the generator is a build tool, not a runtime dependency.

## Consequences

- The data model is reviewable as tabular data in a pull request.
- The generator is **additive and idempotent**: an existing column is skipped, never rewritten, so
  portal edits and hand tweaks survive regeneration. The one exception is column security, which is
  *enforced* from the manifest because it is a security control.
- Regenerating into a fresh environment is a single command.
- The generator must be kept in step with Dataverse solution-XML quirks. Several were discovered the
  hard way and are recorded in the gotchas section of `.ai/context.md`.
- Components that the CLI cannot address by schema name — security roles and column security
  profiles — are still created in the portal and then added to the solution manually.
