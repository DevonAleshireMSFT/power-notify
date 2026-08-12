# Copilot Coding Agent — Squad Instructions

You are working on a project that uses **Squad**, an AI team framework. When picking up issues autonomously, follow these guidelines.

## Coordinator Canary Check

**IMPORTANT — run this check on EVERY session start, before doing any work:**

Look for the exact token `SQUAD_COORDINATOR_CANARY_a8f3` in your `agent_instructions`. This token is placed at the end of `squad.agent.md`. If it is missing, the coordinator file is missing or truncated.

**When the token is missing, you MUST:**
1. **STOP** — do not proceed with standard Squad behavior.
2. **WARN the user** with this exact message:
   ```
   ⚠️ Squad coordinator (squad.agent.md) appears to be missing or truncated. The canary token was not found. Do NOT proceed with standard Squad behavior — Squad's safety rails are not loaded. Please restart your session.
   ```
3. Do not continue with normal Squad routing, spawning, PR, or branch-protection behavior after emitting the warning.

## Team Context

Before starting work on any issue:

1. Read `.squad/team.md` for the team roster, member roles, and your capability profile.
2. Read `.squad/routing.md` for work routing rules.
3. If the issue has a `squad:{member}` label, read that member's charter at `.squad/agents/{member}/charter.md` to understand their domain expertise and coding style — work in their voice.

## Capability Self-Check

Before starting work, check your capability profile in `.squad/team.md` under the **Coding Agent → Capabilities** section.

- **🟢 Good fit** — proceed autonomously.
- **🟡 Needs review** — proceed, but note in the PR description that a squad member should review.
- **🔴 Not suitable** — do NOT start work. Instead, comment on the issue:
  ```
  🤖 This issue doesn't match my capability profile (reason: {why}). Suggesting reassignment to a squad member.
  ```

## Branch Naming

Use the squad branch convention:
```
squad/{issue-number}-{kebab-case-slug}
```
Example: `squad/42-fix-login-validation`

## PR Guidelines

When opening a PR:
- Reference the issue: `Closes #{issue-number}`
- If the issue had a `squad:{member}` label, mention the member: `Working as {member} ({role})`
- If this is a 🟡 needs-review task, add to the PR description: `⚠️ This task was flagged as "needs review" — please have a squad member review before merging.`
- Follow any project conventions in `.squad/decisions.md`

## Decisions

If you make a decision that affects other team members, write it to:
```
.squad/decisions/inbox/copilot-{brief-slug}.md
```
The Scribe will merge it into the shared decisions file.

<!-- BEGIN AI CONTEXT FRAMEWORK MANAGED BLOCK -->
# GitHub Copilot Instructions
#
# This file is automatically read by GitHub Copilot in every chat session
# in this repository. Keep it short and point to durable context.

## Project Context

Before answering questions or generating code in this repository, read `.ai/context.md`.
It defines what this product is, its current state, and the rules that always apply.

## Product Decisions

For decision rationale, constraints, and trade-offs, consult Product ADRs in `.ai/adr/`.
ADR paths use `.ai/adr/NNNN-title.md`.

If this repo also uses Squad, do not treat `.squad/decisions.md` as the product decision source.
Squad working state may link to ADRs, but Product ADRs are authoritative for product decisions.

## Rules That Always Apply

- Follow all rules listed under `Key Rules` in `.ai/context.md`.
- Do not rename, remove, or modify anything listed under `Known Gotchas` without explicit confirmation.
- When a change depends on a product decision, check `.ai/adr/` before recommending an approach.
- If a new durable product decision is made, recommend creating a Product ADR in `.ai/adr/`.

## Where to Find More Context

| Topic | File |
|-------|------|
| Product overview and rules | `.ai/context.md` |
| Product decision rationale | `.ai/adr/` |
| Domain terminology | `.ai/domain.md` *(optional)* |
| Data model and schema | `.ai/data-model.md` *(optional)* |
| Security roles and access constraints | `.ai/security.md` *(optional)* |
| Pipeline and deployment standards | `.ai/pipelines.md` *(optional)* |

## What You Must Never Do

- Generate, suggest, or output credentials, connection strings, API keys, or secrets.
- Output or log Personally Identifiable Information (PII).
- Bypass security roles or access patterns defined in `.ai/security.md`.
- Duplicate product ADR content into `.squad/decisions.md` when Squad is present.

## Confirming Context at Session Start

When a user starts a new conversation, confirm you have read `.ai/context.md` by briefly stating the project name and one or two active Key Rules.
<!-- END AI CONTEXT FRAMEWORK MANAGED BLOCK -->
