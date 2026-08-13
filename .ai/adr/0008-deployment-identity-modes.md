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
   There is no service principal option. This constrains the *connector*; it does not constrain
   the webhook path described below.
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
| Teams / Adaptive Card | **Not available via the Teams connector.** A **Teams webhook** is a candidate and is not yet ruled out - see below |

### The Teams webhook path (candidate, unverified)

The `When a Teams webhook request is received` trigger is installed in a target channel and posts
adaptive cards there. Power Notify would only make an HTTP POST to a URL, which means:

- **No Teams connection reference at all**, so no service account and no non-shareable connection
- The webhook URL is configuration data and fits `pnfy_teamsdestination` naturally
- Identity is decentralised: the receiving flow is owned by a channel owner, not by Power Notify

**Do not treat this as free.** A Teams webhook URL is a bearer credential: anyone holding it can
post to that channel. This project has already been burned once by a callable URL committed as if
it were configuration. If this path is adopted, the URL must be held in a **Secret**-type
environment variable or Key Vault, never a plain text column, and the trigger's authentication
option must be set to something narrower than "Anyone".

Until this is tested in the target cloud, Mode B should be planned as **email-only**, with Teams
treated as a likely addition rather than a confirmed one.

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
3. Does the `When a Teams webhook request is received` path work in the target cloud, and is it
   approvable? If yes, Mode B gains Teams and the biggest limitation in this ADR disappears. Note
   that "Workflows" appearing as the sender does **not** by itself prove which mechanism was used:
   Microsoft renamed the Flow bot to "Workflows" in Teams, so the Flow Bot poster, the User
   poster, and the webhook path can all surface under that name.
4. Is there an approved Graph-based path for Teams posting via an app registration? This would
   need the HTTP with Microsoft Entra ID connector and `ChannelMessage.Send` application
   permission, and is likely to face the same approval friction as a service account.
