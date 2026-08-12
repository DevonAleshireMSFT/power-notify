# 0005 — Table ownership model

- **Status:** accepted
- **Date:** 2026-08-12

## Context

Dataverse table ownership (Organization vs User/Team) is fixed at table creation and **cannot be
changed afterwards**. It determines which privilege depths are even available: organization-owned
tables support only Organization depth, while user/team-owned tables support User, Business Unit,
Parent:Child Business Unit, and Organization.

A recurring requirement was that a support analyst should see the notification history for their
own application, but not every application's traffic.

## Decision

| Group | Tables | Ownership |
|---|---|---|
| Configuration | definition, channel binding, template, recipient rule, Teams destination, token, calling application | **Organization** |
| Suppression | suppression entry | **Organization** |
| Operational | notification request, delivery attempt, payload snapshot | **User / Team** |

Log rows are owned by the calling application's support team, sourced from
`pnfy_callingapplication.pnfy_supportteam`.

## Consequences

- Configuration security is simple role math with no business-unit filtering, which suits shared
  platform config that everyone reads and few people write.
- Support scoping is achieved with no extra mechanism: the Support Analyst role reads request and
  attempt at **Business Unit** depth, and team ownership does the rest.
- The request-to-attempt and request-to-payload relationships cascade **Assign** and **Share** so
  reassigning a request keeps its children consistently scoped.
- Suppression entries are Organization-owned because they have no per-application scoping value and
  are high-volume and ephemeral; ownership churn on them would be pure overhead.
- This decision is irreversible without recreating the tables.
