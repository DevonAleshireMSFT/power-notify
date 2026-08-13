---
adr: 0008
title: Deployment identity model - Dataverse, email sender, and Teams
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0008 — Deployment identity model: Dataverse, email sender, and Teams

## Context

Power Notify's flows need identities to own their connection references. "Do we have a service
account?" looked like one question. It is three, and they have different answers.

The confusing term is **service account**. It conflates two things with very different approval
paths:

- a **service principal** — an Entra app registration with no licence, no mailbox, no interactive
  sign-in, and no human owner of record
- a **service user account** — a licensed account with a mailbox, subject to MFA and conditional
  access policy, owned by a named person

DoD approval friction is largely against the second. Treating the two as one thing caused an
earlier revision of this ADR to overstate its constraints.

### Platform facts

1. **The Dataverse connector accepts service principal authentication in DoD.** Confirmed
   2026-08-13. This was previously an open question and is now settled.
2. **The Office 365 Outlook connector sends from the connection owner's mailbox** — but the
   `Send an email (V2)` action exposes a **From (Send as)** parameter, so the visible sender can be
   a different mailbox that the owner is permitted to send as.
3. **The Microsoft Teams connector authenticates only as a signed-in user.** Its authentication
   types are all user logins and the connection is explicitly **not shareable**. This constrains
   the *connector*; it does not constrain the webhook path.
4. **Flow Bot is not supported in GCC, GCC High, or DoD.** Teams posts through the connector must
   use the `User` poster.

**Observed rendering, 2026-08-12.** With the User poster a card does not masquerade as a personal
message. It renders as the **Workflows app** attributed *on behalf of* the connection owner, so the
automation framing stays visible. One observed message showed the sender as the unresolved token
`botcards_sent_on_behalf_of_user_display_name`, which confirms the on-behalf-of mechanism and shows
that the attributed identity's display name must be set deliberately or it surfaces to end users.

## Decision

Treat identity as **three independent questions**, not one deployment mode switch.

### 1. Dataverse identity — service principal

All Dataverse access runs as an **application user backed by a service principal**, assigned the
`pnfy Service` role. No licence, no mailbox, no interactive sign-in, no personal owner.

This covers enqueue, dispatch, delivery-attempt logging, payload snapshots, retry, the stuck
request monitor, and purge — the entire spine of the product.

### 2. Email sender identity — shared mailbox with Send As

The Outlook connection must be owned by a licensed user; the connector cannot escape user auth.
But the **visible sender is decoupled from the connection owner** through `From (Send as)`.

- **Connection owner** — any ordinary licensed user. Not a special account.
- **Visible sender** — a **shared mailbox**, unlicensed under 50 GB, owned by the team rather than
  by a person.

Two ways to grant the permission:

| Option | How | Trade-off |
|---|---|---|
| **Mail-enabled security group** *(recommended)* | Grant **Send As** on the shared mailbox to a mail-enabled security group; the connection owner is a member | Swapping the connection owner becomes a group membership change — no Exchange ticket, no waiting on an admin |
| **Direct Send As** | Grant **Send As** on the shared mailbox to the named connection owner | Fewer moving parts to set up, but every owner change needs an Exchange administrator |

Prefer the group. The direct grant is supported and is reasonable for a single small deployment
where no group exists yet, but it recreates the lifecycle coupling this decision exists to remove.

Use **Send As**, not **Send on Behalf** — the latter renders as "owner on behalf of mailbox".

### 3. Teams identity — webhook, not connector

Teams delivery uses the **`When a Teams webhook request is received`** path. A channel owner
installs a receiving workflow in their channel; Power Notify posts an Adaptive Card to the
resulting URL. Power Notify therefore holds **no Teams connection reference and no Teams user
identity**.

**Verified 2026-08-13, GCC High (GFIM).** A test endpoint exists, is reachable, and enforces
OAuth — an unauthenticated POST returns:

```
HTTP 401
{"error":{"code":"DirectApiAuthorizationRequired",
          "message":"The OAuth authorization scheme is required."}}
```

This confirms the endpoint half of the design and **corrects an assumption**: with the
tenant-restricted trigger mode, the sender is *not* a plain HTTP POST. It must present an Entra
bearer token. That token can come from the **same service principal** already used for Dataverse,
so the decision still holds — no user identity is required — but the sender flow needs a token
acquisition step, and the correct token audience is not yet established.

End-to-end delivery is deliberately **deferred until the sender flow exists**. Until then Teams
stays gated behind `pnfy_TeamsEnabled`, which already defaults to `no`.

### The webhook trade-offs

Adopting the webhook does not make Teams free:

- **Credential exposure depends on the trigger's auth mode.** Under `Anyone` the URL is a bearer
  credential and anyone holding it can post to the channel. Under the **tenant-restricted** mode
  observed in GFIM the URL alone is useless without a valid token, which substantially reduces the
  risk — this is the mode to prefer. Treat the URL as sensitive regardless: store it
  column-secured, never as plain configuration. This project has already been burned once by a
  callable URL committed as if it were configuration.
- **Lifecycle moves, it does not vanish.** The receiving workflow is owned by an individual channel
  owner. If that person leaves, the channel's delivery dies — and it fails per channel, which is
  harder to notice than one central connection breaking.
- **Per-channel setup burden.** Every target channel needs a human to install a workflow. One
  connector connection reaches many channels; this does not.
- **Channels only.** The webhook cannot deliver a direct message to an individual.
- **The HTTP action is premium.**

## Consequences

- **Only one email transport gets built.** `pnfy_EmailTransport` was introduced to allow a
  Dataverse-email-with-queue path that existed solely to avoid the mailbox-owner problem. Send As
  solves that problem better. Implement `Connector` only. Keep the environment variable as a seam,
  and make the dispatcher **fail loudly** on any unimplemented value — a silent skip would violate
  the recorded-outcome rule below.
- **The sender address is configuration data, not a single environment variable.** One environment
  may serve several teams or commands, each with its own mailbox. This requires:
  - `pnfy_DefaultSenderAddress` — the environment default
  - a sender override column on `pnfy_CallingApplication`
- **`pnfy_TeamsDestination` needs schema changes.** `pnfy_teamid` and `pnfy_channelid` are
  currently **required**, which a webhook-only destination cannot satisfy. This requires:
  - a destination-type discriminator so a row declares connector or webhook
  - a webhook URL column, **column-secured**, because the URL is a credential
  - relaxing `pnfy_teamid` and `pnfy_channelid` to optional
- **The dispatcher no longer "runs as the service account."** It runs as the application user.
- **The existing fail-closed defaults already fit.** `pnfy_TeamsEnabled` and
  `pnfy_AdaptiveCardsEnabled` default to `no`, so an environment where the Teams spike has not been
  completed is correct out of the box.
- The dispatcher must treat "channel disabled" as a **first-class, recorded outcome** — a delivery
  attempt with status `Skipped` and a reason — not a silent no-op. Silence is indistinguishable
  from data loss.
- Consumers must not assume a channel exists. The runtime contract already returns acceptance
  rather than delivery outcome (ADR 0003), so this does not change the contract — but the consumer
  onboarding guide must state that channel availability is environment-dependent.
- **Sent items land in the connection owner's mailbox** unless Exchange is configured to copy them
  to the shared mailbox. Configure it, or the sent-mail audit trail scatters across individuals.

## Open questions

These are unverified and must not be assumed:

1. Does an Adaptive Card actually **render in the channel** when posted? The endpoint accepting a
   request does not prove the receiving workflow succeeds. The interesting failure is a 2xx with no
   visible card — check the receiving flow's run history for `BotNotInConversationRoster`, which
   would mean the webhook does not escape the Flow Bot limitation after all. Tracked as issue #23.
2. **Which token audience** does the direct-invoke endpoint expect? Candidates tried without a
   cached token: `service.flow.microsoft.us`, `api.high.powerplatform.microsoft.us`,
   `high.flow.microsoft.us`, `service.powerapps.us`. Establish this before building the sender.
3. Can the **Dataverse service principal** obtain that token, or does it need separate consent or
   an app permission grant?
4. Does the DoD cloud behave the same as GCC High here? GCC High evidence does not transfer.
5. Do any recipient rules need Teams **direct messages**? The webhook path serves channels only, so
   a DM requirement would force the connector back in for that case alone.
6. Is a shared mailbox with Send As obtainable in the target DoD environment, and can the grant be
   made to a mail-enabled security group rather than to a named user?
