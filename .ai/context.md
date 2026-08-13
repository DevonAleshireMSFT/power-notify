---
project: Power Notify
platform: Power Platform / Dataverse
cloud: GCC High (target: GCC High + DoD)
context-version: 1.0.0
last-updated: 2026-08-12
owner: Devon Aleshire
review-cadence: every-sprint
---

# Power Notify — AI Context

> Durable product context for humans and AI assistants. Read this first, then follow links for detail.

---

## Boundary

- `.ai/` is durable product knowledge: WHAT this product is and WHY constraints exist.
- Product decisions live in `.ai/adr/NNNN-title.md`.
- `.squad/` is AI-team working state: HOW work was routed, decided, and done.
- If Squad is present, `.squad/decisions.md` links to Product ADRs; it does not restate them.

---

## What This Is

Power Notify is a shared notification service for Power Platform solutions. Consuming apps and
flows pass a **message key** plus runtime values; Power Notify decides who to notify, on which
channels, with what content, and records what happened.

Without it, notification logic scatters across every app and flow: duplicated email bodies,
hardcoded recipients and Teams channel IDs, inconsistent error handling, and no way to answer
"why didn't that person get notified?" without opening individual flow runs. Power Notify
centralises that into configurable, traceable, supportable infrastructure that multiple internal
solutions call through a single contract.

---

## Current State

- ✅ Dataverse data model complete and verified in Power Notify DEV — 11 tables, 126 columns,
  13 global choices, 20 relationships, 7 alternate keys
- ✅ Column security enabled on the 5 sensitive columns
- ✅ Schema-as-source pipeline: CSV manifests, generator, and a pack/import round trip
- ✅ Security model — 7 roles and 4 column security profiles, verified in Power Notify DEV
- ✅ 15 environment variables, fail-closed defaults, no environment-specific values shipped
- ⏳ Connection references — identity model now settled (ADR 0008): Dataverse uses a service
  principal, email uses a shared mailbox with Send As, Teams uses a webhook pending the issue #23
  spike
- 🔲 Cloud flows (enqueue contract, dispatcher, channel senders, retry, monitor, purge)
- 🔲 Forms, views, dashboards, and the administration app sitemap
- 🔲 Configuration data migration package
- 🔲 Pilot with one consuming application

---

## Architecture Summary

Layers, outermost first:

- **Contract** — a single child flow, `PN | Enqueue Notification`. The only supported entry point.
  It validates, writes a queued request row, and returns immediately.
- **Configuration** — organization-owned Dataverse tables: notification definitions, channel
  bindings, templates, recipient rules, Teams destinations, tokens, calling applications.
- **Orchestration** — `PN | Dispatch Notification`, triggered by the queued row, running as the
  **application user** backed by a service principal. Resolves recipients, renders templates, calls
  per-channel senders.
- **Delivery** — channel sender child flows (email, Teams message, Adaptive Card) behind
  environment-variable capability flags.
- **Observability** — request, delivery attempt, payload snapshot, and suppression tables, plus
  retry, stuck-request monitor, and purge flows.
- **Security** — seven roles, column security profiles on content columns, and team-owned log rows
  that give support analysts business-unit-scoped visibility.

Delivery is **asynchronous**: the caller receives acceptance, not a delivery outcome.

---

## Key Rules

> These rules must be followed in every AI interaction with this codebase.

- **Always pass `--environment 24a9495b-1431-e2e3-8a43-850300d8ae50` explicitly on every `pac`
  command.** The ambient auth profile has silently reverted mid-session and sent an import to the
  wrong environment. Do not rely on `pac org select` persisting.
- **Schema changes go through the manifests in `schema/*.csv` and `build/Build-PnfySchema.ps1`,
  not hand-edited solution XML.** The generator is additive and idempotent.
- **Validate one slice end to end before generating in bulk.** Bulk generation of solution XML has
  repeatedly cost several failed import cycles; one validated example costs one.
- **Power Notify must deploy without a service *user account*.** Identity is three separate
  questions, not one (ADR 0008): Dataverse runs as a **service principal**; email sends from a
  **shared mailbox via Send As**, so the Outlook connection owner can be any ordinary licensed
  user; Teams uses a **webhook**, so Power Notify holds no Teams identity at all. Do not conflate
  a service principal with a licensed service user account — they have different approval paths.
- **Grant Send As through a mail-enabled security group, not to a named person.** Swapping the
  Outlook connection owner should be a group membership change, never an Exchange ticket. A direct
  Send As grant to a named user is supported but recreates the lifecycle coupling.
- **A channel that is unavailable must be recorded, never silently skipped.** Every disabled or
  unresolvable channel produces a delivery attempt with status `Skipped` and a reason. Silence is
  indistinguishable from data loss.
- **Never hardcode recipients, Teams team or channel IDs, org URLs, or message bodies** in a flow
  or web resource. They are configuration data or environment variables.
- **Message keys and published templates are immutable.** Retire, never rename. A new template
  version is a new row, not an edit.
- **The enqueue contract's inputs are a public API.** Additive changes only; a breaking change
  ships as `V2` alongside `V1` with a deprecation window.
- **Token values are HTML-encoded or JSON-escaped at render time** unless the token's
  administrator-only `pnfy_allowhtml` flag is set. That flag is the injection control.
- **Never commit secrets.** `artifacts/` and `*.zip` are gitignored; commit unpacked source only.
- **Verify solution membership after creating anything in the maker portal.** Components live in
  the environment; a solution is only a manifest pointing at them.

---

## Known Gotchas

> Non-obvious constraints that will cause errors if ignored.

- **Table ownership is permanent** and cannot be changed after creation. Config tables are
  Organization-owned; request, attempt, and payload are User/Team-owned deliberately.
- **The publisher prefix `pnfy` and option-value prefix `63000` are permanent.** Changing either
  means recreating every component.
- **Alternate key columns must be roughly 450 characters or fewer.** `nvarchar(850)` is 1700 bytes
  and exceeds the 900-byte SQL index limit, so the key fails to build. Maker-portal primary
  columns default to 850.
- **Relationships must be registered in `Other/Relationships.xml`.** Writing only the definition
  file under `Other/Relationships/` is silently ignored by the packer.
- **Relationship role types:** `1` is the referencing role and carries the nav pane options plus
  the lookup *schema* name; `0` is the referenced role and carries the relationship name. Entity
  and attribute names in relationship XML use schema casing, not logical casing.
- **Local boolean option set names must be unique organization-wide** — qualify them as
  `<entitylogicalname>_<columnlogicalname>`.
- **Global option sets must be declared as root components** in `Other/Solution.xml`, or import fails.
- **A column cannot be added to a column security profile** unless column security is enabled on
  the column itself.
- **Flow Bot is not supported in GCC, GCC High, or DoD.** This constrains the Teams *connector*
  only. Power Notify uses the **Teams webhook** path instead (ADR 0008), so it holds no Teams
  connection reference. A message whose sender reads "Workflows" does not indicate which mechanism
  produced it, because Microsoft renamed the Flow bot to "Workflows".
- **A Teams webhook URL is a bearer credential.** Anyone holding it can post to that channel. It
  belongs in a column-secured field, never plain configuration. The webhook also serves **channels
  only** — it cannot direct-message an individual — and its receiving workflow is owned by a
  channel owner, so delivery dies per channel if that person leaves.
- **The Office 365 Outlook connector sends from the connection owner's mailbox by default**, but
  `Send an email (V2)` exposes **From (Send as)**, so the visible sender can be a shared mailbox
  the owner may send as. Use Send As, not Send on Behalf — the latter renders as "owner on behalf
  of mailbox". Sent items land in the owner's mailbox unless Exchange is configured to copy them
  to the shared mailbox.
- **Adaptive Card behaviour in DoD is unverified.** It is gated behind `pnfy_AdaptiveCardsEnabled`
  and needs a hands-on test before being enabled.
- **The legacy `NotificationGenerator` solution is reference only.** Its web resource contained a
  live Logic Apps shared access signature. The value is redacted in the repo, but the trigger
  still requires rotation in the source environment.

---

## Product Decisions

Product ADRs live in `.ai/adr/` using the path format `.ai/adr/NNNN-title.md`.

| ADR | Decision | Status |
|-----|----------|--------|
| `0001-publisher-and-prefix.md` | Publisher `powernotify`, prefix `pnfy`, option-value prefix `63000` | accepted |
| `0002-rebuild-not-refactor.md` | Rebuild rather than refactor the original solution | accepted |
| `0003-asynchronous-queued-delivery.md` | Callers enqueue a request row; a dispatcher delivers | accepted |
| `0004-message-key-not-guid.md` | Callers address notifications by logical message key, never a GUID | accepted |
| `0005-table-ownership-model.md` | Config tables organization-owned; log tables team-owned | accepted |
| `0006-two-solution-layering.md` | Two solutions (Core, Samples), not five | accepted |
| `0007-schema-as-source.md` | Schema authored as CSV manifests expanded into solution XML | accepted |
| `0008-deployment-identity-modes.md` | Dataverse runs as a service principal; email sends from a shared mailbox via Send As; Teams uses a webhook | accepted |

---

## Environments

| Environment | ID | Cloud | Purpose |
|---|---|---|---|
| Power Notify DEV | `24a9495b-1431-e2e3-8a43-850300d8ae50` | GCC High | Active development |
| *(Test)* | not provisioned | GCC High | Planned |
| *(Prod)* | not provisioned | GCC High / DoD | Planned |

Solutions move between GCC High and DoD through DoD-Safe. Every transfer, DoD import or publish,
and source-environment test is a discrete, human-performed step. **GCC High validation is package
and metadata validation only; it does not prove DoD compatibility** — track evidence per
environment. Anything created or modified in DoD must return as an unmanaged export, then be
unpacked, inspected, and committed before it becomes authoritative.

---

## Where to Look

| Topic | File |
|-------|------|
| Product decisions | `adr/` |
| Column definitions | `../schema/pnfy-columns.csv` |
| Lookups and cascade behaviour | `../schema/pnfy-relationships.csv` |
| Alternate keys | `../schema/pnfy-keys.csv` |
| Column security | `../schema/pnfy-secured-columns.csv` |
| Schema generator | `../build/Build-PnfySchema.ps1` |
| Unpacked solution source | `../solutions/PowerNotifyCore/` |
| Legacy solution (reference only) | `../legacy/NotificationGenerator_1_0_0_3/` |
