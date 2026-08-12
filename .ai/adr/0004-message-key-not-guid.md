---
adr: 0004
title: Message key, not GUID
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0004 — Message key, not GUID


## Context

The prior implementation identified a notification by its Dataverse row GUID: the calling app
passed a record ID, and the flow performed a `GetItem` against `demo_notifications`.

Dataverse GUIDs are generated per environment. A configuration row created in Dev has a different
ID in Test and Prod. Every caller would therefore break on the first ALM promotion, which defeats
the premise of a reusable service.

## Decision

Callers address notifications by a stable logical **message key**.

- `pnfy_messagekey` is the primary column of `pnfy_notificationdefinition`, 100 characters.
- It carries a unique alternate key, `pnfy_MessageKeyUnique`.
- Message keys are immutable once published. To retire a notification, deactivate it; never rename.

## Consequences

- Callers are portable across environments without change.
- Configuration data migration becomes a deterministic upsert keyed on the message key, rather than
  an ID-mapping exercise.
- The alternate key requires the column to stay within the 900-byte SQL index limit, which is why
  the column is 100 characters rather than the maker-portal default of 850. See the gotchas in
  `.ai/context.md`.
- The request table stores a `pnfy_messagekeysnapshot` copy so history remains readable even if the
  definition is later retired.
