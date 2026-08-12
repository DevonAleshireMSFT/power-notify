---
adr: 0003
title: Asynchronous queued delivery
status: accepted
date: 2026-08-12
deciders: Devon Aleshire
reviewers: Devon Aleshire
applies-to: Power Notify
supersedes: null
superseded-by: null
---

# 0003 — Asynchronous queued delivery


## Context

A notification service can deliver either synchronously inside the caller's flow, or accept the
request and deliver it out of band. The choice determines the shape of the public contract, the
failure model, and how the platform behaves under burst load.

The prior implementation was synchronous and returned `success: true` unconditionally, regardless
of whether anything was actually sent.

## Decision

Delivery is asynchronous:

1. The caller invokes `PN | Enqueue Notification`, which validates and writes a
   `pnfy_notificationrequest` row with status **Queued**, then returns immediately.
2. A Dataverse-triggered dispatcher picks up queued rows, resolves recipients, renders templates,
   calls channel senders, and writes delivery attempt rows.

## Consequences

- **The enqueue contract cannot return a delivery outcome.** It returns acceptance:
  `Accepted`, `NotificationRequestId`, `RequestNumber`, `CorrelationId`, `Status`,
  `ValidationErrors`. Callers needing the result must poll the request row. This is the central
  trade-off and must be stated in the consumer onboarding guide.
- A slow or failing channel cannot block the calling business process.
- Bursts are absorbed by the queue rather than by connector throttling in the caller's flow.
- Retry, stuck-request detection, and purge become straightforward because every request is a row
  with a status, rather than transient flow-run state.
- Validation failures *are* returned synchronously, because they happen before queuing.
