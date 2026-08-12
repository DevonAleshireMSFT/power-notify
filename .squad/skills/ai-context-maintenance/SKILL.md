---
name: ai-context-maintenance
description: Keep .ai/ product context current after work sessions. Use when a session changed the shipped product — new tables, columns, flows, roles, environments, or a decision that alters architecture or constraints. Defines exactly which parts of .ai/ may be updated automatically and which require a human.
confidence: medium
---

# Keeping `.ai/` current

`.ai/` is **durable product knowledge**: WHAT Power Notify is and WHY its constraints exist.
`.squad/` is **AI-team working state**: HOW work was routed and decided.

These are different things with different lifetimes. A session log is disposable; a product
constraint outlives the team that discovered it. Never let one leak into the other.

## The hard boundary

| Area of `.ai/` | Scribe may update automatically? |
|---|---|
| `context.md` → **Current State** bullets | ✅ Yes — this is status, and it goes stale fastest |
| `context.md` → **last-updated** front-matter | ✅ Yes — but only when something else actually changed |
| `context.md` → **Product Decisions** table row | ✅ Yes — when an ADR *file* is added or its status changes |
| `context.md` → **Known Gotchas** | ⚠️ Only to add a gotcha proven by a concrete failure this session |
| `context.md` → **Key Rules**, **Architecture Summary**, **What This Is** | ❌ No — propose, do not edit |
| `adr/*.md` → new ADR content | ❌ No — propose, do not author |
| `adr/*.md` → status change to `superseded` / `deprecated` | ❌ No — propose, do not edit |

**Why the asymmetry:** status is observable from the repository and safe to derive. Rules,
architecture, and decisions are *judgements*. An agent that quietly rewrites a product decision
because a session went a certain way has destroyed the record of why the decision was made.

## When to run

After a work session that changed the shipped product:

- Tables, columns, choices, relationships, keys, roles, or profiles added or removed
- Flows, environment variables, or connection references added or removed
- A new environment provisioned, or an environment fact changed
- A platform constraint discovered the hard way (a failed import that revealed a rule)

**Do not run** for sessions that only changed `.squad/` state, documentation wording, or tooling
that does not alter the product.

## Procedure

1. **Read** `.ai/context.md`. It is a normal git-tracked file — edit it with ordinary file writes,
   not the `squad_state_*` tools. Those tools are for `.squad/` state only.

2. **Reconcile Current State** against what is actually true in the repository and environment.
   Move items between ✅ / ⏳ / 🔲. Prefer verified counts over adjectives: "11 tables, 126
   columns, 20 relationships" beats "the data model is largely complete."

3. **Add a gotcha only with evidence.** If the session hit a platform constraint that cost real
   time, add one line stating the constraint and the symptom. No speculation.

4. **Update the ADR table** if an ADR file was added. Do not invent the row — read the ADR's
   front-matter and copy `adr`, `title`, and `status`.

5. **Bump `last-updated`** to today in `YYYY-MM-DD` form, but **only if steps 2–4 changed
   something.** The repository runs a staleness check; bumping the date without a real change
   defeats that check and is worse than leaving it stale.

6. **Propose, do not author.** For anything in the ❌ rows above, write a proposal to the decision
   inbox instead:

   `.squad/decisions/inbox/scribe-adr-proposal-{slug}.md`

   State the proposed decision, why the session suggests it, and which ADR number it would take.
   A human or the Lead decides. Never create `.ai/adr/*.md` directly.

7. **Verify before finishing.** Run:

   ```
   npm run check
   ```

   This must report `0 ERROR`. If it does not, fix your own edit or revert it. Never leave the
   conformance gate red.

## Conformance rules that bite

These are enforced by `scripts/validate-ai-context.mjs` and will fail CI:

- `last-updated` must be `YYYY-MM-DD`. Not a timestamp, not a placeholder.
- `review-cadence` must be one of: `every-sprint`, `monthly`, `quarterly`, `biannual`, `annual`.
- Every ADR needs all of: `adr`, `title`, `status`, `date`, `deciders`, `reviewers`,
  `applies-to`, `supersedes`, `superseded-by`.
- `adr` must be four digits, unquoted, and match the filename prefix. `adr: '0001'` fails —
  the front-matter parser does not strip quotes.
- `status` must be one of: `proposed`, `accepted`, `superseded`, `deprecated`.
- `supersedes` / `superseded-by` must be an ADR filename or the literal `null`.

## Relationship to `.squad/decisions.md`

`decisions.md` records *that* the team decided something and who decided it. A product ADR records
*why* the product is shaped that way and what it costs. When a decision in `decisions.md` rises to
product significance, link to the ADR from the decision entry — do not restate the ADR content in
`.squad/`, and do not copy session narrative into `.ai/`.
