---
adr: 0006
title: Two-solution layering
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0006 — Two-solution layering


## Context

A common pattern for a reusable platform capability is to split it into several solutions — core
schema, security, automation, app, samples — so each can be released independently.

Power Notify's confirmed reuse scope is **multiple internal solutions inside a single environment**,
maintained by one team, released together.

## Decision

Two solutions:

| Solution | Contents | Ships to |
|---|---|---|
| `PowerNotifyCore` | Tables, choices, relationships, alternate keys, security roles, column security profiles, environment variables, connection references, flows, administration app | Dev → Test → Prod (managed) |
| `PowerNotifySamples` | Sample definitions, templates, test harness | Dev and Test only — never Prod |

The five-way split was explicitly considered and rejected.

## Consequences

- No cross-solution dependency ordering to manage on import, and faster imports.
- No layering complexity from components spread across solutions with independent versions.
- Everything releases together, which matches how the team actually works today.
- **Revisit trigger:** if Power Notify is ever distributed to other tenants, or consumed on
  independent release cadences, split into Core / Automation / App at that point. Nothing in the
  current structure prevents that later split.
- Sample and demo content cannot accidentally reach production, because it lives in a solution that
  is never deployed there.
