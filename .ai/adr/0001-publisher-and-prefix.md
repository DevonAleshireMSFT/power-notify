# 0001 — Publisher and prefix

- **Status:** accepted
- **Date:** 2026-08-12

## Context

The original solution was built under a throwaway publisher: display name `Demo`, unique name
`demo_publisher`, customization prefix `demo`, option-value prefix `34563`. Power Notify is
intended as reusable infrastructure that other internal solutions depend on, so its schema names
become a long-lived public surface.

A Dataverse publisher prefix and option-value prefix **cannot be changed after any component is
created under them**. Correcting this later would mean recreating every table, column, choice,
flow, and app.

## Decision

Create a dedicated publisher and use it for every Power Notify component:

| Field | Value |
|---|---|
| Display name | `Power Notify` |
| Unique name | `powernotify` |
| Customization prefix | `pnfy` |
| Option-value prefix | `63000` |

`pnfy` was chosen over the alternative `pwrnfy` for shorter schema names. Neither abbreviation is
self-explanatory to a newcomer; clarity comes from the publisher display name and this document,
not from the prefix itself.

## Consequences

- Every schema name is `pnfy_*`, and every custom option value begins `63000`.
- This decision is effectively irreversible; revisiting it means rebuilding the solution.
- The legacy `demo`-prefixed solution cannot be migrated into this publisher. It is retained as
  read-only reference only (see ADR 0002).
