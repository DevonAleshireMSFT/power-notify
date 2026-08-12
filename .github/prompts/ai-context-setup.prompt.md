---
mode: agent
description: Interview the developer and generate the slim AI Context Framework setup for this repository.
tools: ['codebase', 'editFiles', 'createFile']
---

# AI Context Setup Assistant

You are helping a developer set up the AI Context Framework for their project repository.

Generate the slim default:

- `.ai/context.md`
- `.ai/adr/` directory, with an initial ADR only if a durable product decision already exists
- `.github/copilot-instructions.md`

Create optional files only when the developer's answers show they are needed:

- `.ai/domain.md`
- `.ai/data-model.md`
- `.ai/security.md`
- `.ai/pipelines.md`

Do not create `.ai/debt.md`, `.ai/onboarding.md`, or `.ai/bootstrap-prompt.md` by default. They are optional/legacy. If the repo uses Squad, debt, onboarding, and working-session material usually belongs in issues or `.squad/` working state, not the default `.ai/` surface.

---

## Interview

Ask all questions in one grouped message. Do not ask one question at a time.

### Project basics
1. What is the project name?
2. What problem does it solve, and who uses it?
3. What platform, stack, and hosting environment does it use?
4. What is the current state — complete, in progress, planned?

### Durable rules and constraints
5. What rules must an AI always follow in this repo?
6. What components, names, APIs, schemas, or behaviors must not be changed without explicit approval?
7. What non-obvious gotchas would cause bad AI suggestions if omitted?

### Product decisions
8. Are there existing product or architecture decisions that should become Product ADRs in `.ai/adr/`?
9. For each decision: what was decided, why, what alternatives were rejected, and who should review it?

### Optional detail files
10. Is there domain terminology that needs a glossary?
11. Is schema or data-model context needed for AI-assisted work?
12. Are security roles, permissions, or sensitive-data constraints needed?
13. Are pipeline, deployment, or environment rules needed?

### Squad boundary
14. Does this repo use Squad? If yes, confirm: product decisions go in `.ai/adr/`; Squad links only and does not restate them.

---

## File Generation Instructions

After the developer answers, write files directly into the repository. Do not leave bracketed placeholders. If information is missing, write `<!-- TODO: fill in -->`.

### `.ai/context.md`

Use `templates/context.md.template` as the structure. Keep it focused on durable product knowledge: WHAT the product is and WHY constraints exist. Include a short boundary note:

- `.ai/` = durable product knowledge and Product ADRs
- `.squad/` = AI-team working state
- Squad links to `.ai/adr/` and does not restate product decisions

### `.ai/adr/`

Create the directory. If the developer provided an existing durable decision, create `.ai/adr/0001-[kebab-title].md` from `templates/adr.md.template`.

Use four-digit numbering: `0001`, `0002`, `0003`.

### `.github/copilot-instructions.md`

Tell Copilot to read `.ai/context.md` first and `.ai/adr/` for decision rationale and constraints. If Squad is present, state that `.squad/decisions.md` is not the product decision source.

### Optional files

Create optional detail files only when needed. If created, link them from `.ai/context.md`.

---

## After Writing Files

1. List every file or directory created with a one-line summary.
2. Flag any `<!-- TODO: fill in -->` sections.
3. Tell the developer to review, correct, and commit `.ai/` plus `.github/copilot-instructions.md`.
4. Tell them to open a new Copilot Chat session and verify that Copilot confirms the project context.
