---
adr: 0002
title: Rebuild rather than refactor
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0002 — Rebuild rather than refactor


## Context

An initial Power Notify proof of concept existed as the unmanaged solution
`NotificationGenerator 1.0.0.3`. A full review found:

- One table with six custom columns, carrying content, channel, and configuration in a single row
- Four flows totalling roughly thirty actions, of which one was a dead stub
- No security roles, no environment variables, no logging, no recipient or template model
- A hardcoded recipient address and a hardcoded Teams channel concept
- A live Logic Apps shared access signature committed in a JavaScript web resource, on a flow whose
  trigger accepted "Anyone"
- The notification identifier was a Dataverse GUID, which differs per environment
- Several silent defects: an unimplemented Teams branch, an off-by-one channel constant, an empty
  "send as" switch case, and a response that always reported success

Separately, the publisher prefix was wrong and is immutable (ADR 0001).

## Decision

Rebuild under the new publisher rather than refactor.

## Consequences

- Because the prefix is immutable, every component had to be recreated regardless of approach.
  Once that is true, "refactor" would mean rebuilding while carrying forward known defects.
- Surviving assets are limited to one sample HTML body, six choice labels, and the channel concept
  — all copy-paste, not migration.
- The legacy solution folder is retained in the repository as reference until the rebuild reaches
  functional parity, then it should be deleted.
- The exposed shared access signature has been redacted from the working tree, but the trigger
  still requires rotation in the source environment. That is tracked as a security action, not
  closed by this decision.
