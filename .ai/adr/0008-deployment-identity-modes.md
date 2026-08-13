---
adr: 0008
title: Deployment identity modes - with and without a service account
status: proposed
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0008 — Deployment identity modes: with and without a service account

## Context

Power Notify's flows need an identity to own connection references. The natural answer is a
dedicated service account, and that is what the architecture has assumed so far.

In DoD environments, service account approval is slow and not guaranteed. Power Notify must
therefore be deployable **without** one, not merely degrade if one is unavailable.

Three platform facts constrain the options, and they are the reason this is an architectural
decision rather than an operations detail:

1. **Flow Bot is not supported in GCC, GCC High, or DoD.** Teams and Adaptive Card posts must use
   the `User` poster, so the message visibly comes from whoever owns the connection.
2. **The Microsoft Teams connector authenticates only as a signed-in user.** Its documented
   authentication types are all user logins, and the connection is explicitly **not shareable**.
   There is no service principal option.
3. **The Office 365 Outlook connector sends from the connection owner's mailbox.** No owner
   mailbox, no email.

A named human owner is not an acceptable substitute in either mode: notifications would appear to
come from an individual, and delivery breaks the moment that person changes role or leaves.

## Decision

Treat identity as a **deployment mode**, and make channel availability a documented function of
that mode rather than something discovered at run time.

### Mode A — service account available

The service account owns all three connection references. Every channel is available. This is the
preferred mode where the account can be approved.

### Mode B — no service account

| Concern | Mechanism |
|---|---|
| Dataverse access | **Application user (service principal).** No license, no mailbox. The Dataverse connector supports service principal authentication |
| Email | **Dataverse email with a queue as sender**, via server-side sync. No connector and no mailbox-owning user; a queue is a Dataverse record, not an account |
| Teams / Adaptive Card | **Not available.** No mechanism posts to Teams without a user identity, given facts 1 and 2 above |

Mode B therefore ships as an **email-only** deployment. That is a real capability reduction and
should be stated plainly to consumers rather than discovered when a Teams notification silently
never arrives.

A new environment variable selects the email transport:

- `pnfy_EmailTransport` — Text — values `Connector` or `DataverseEmail`. No default; it must be a
  conscious per-environment choice.

## Consequences

- **The existing fail-closed defaults already accommodate Mode B.** `pnfy_TeamsEnabled` and
  `pnfy_AdaptiveCardsEnabled` default to `no`, so a Mode B environment is correct out of the box
  and a Mode A environment is the one that must consciously opt in. This was not designed for
  this purpose but happens to be exactly right.
- The dispatcher must treat "channel disabled" as a **first-class, recorded outcome** — a delivery
  attempt with status `Skipped` and a reason — not a silent no-op. Otherwise Mode B looks like
  data loss.
- Two email code paths must be built and tested. The Dataverse email path is not a fallback bolted
  on later; it is a supported transport with its own test evidence.
- Consumers must not assume a channel exists. The runtime contract already returns acceptance
  rather than delivery outcome (ADR 0003), so this does not change the contract — but the consumer
  onboarding guide must state that channel availability is environment-dependent.
- Queue-based email requires server-side sync configuration in the target environment. That is a
  human, environment-specific setup step, and it is on the deployment checklist rather than in the
  solution.

## Open questions

These are unverified and must not be assumed:

1. Does the Dataverse connector accept service principal authentication for connection references
   in **DoD** specifically? Verified behaviour in commercial does not transfer.
2. Is server-side sync with a queue mailbox approved and available in the target DoD environment?
3. Is there an approved Graph-based path for Teams posting via an app registration that would
   restore Teams in Mode B? This would need the HTTP with Microsoft Entra ID connector and
   `ChannelMessage.Send` application permission, and is likely to face the same approval friction
   as a service account.
