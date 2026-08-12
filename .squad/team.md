# Squad Team

> power-notify

## Coordinator

| Name | Role | Notes |
|------|------|-------|
| Ben Franklin | Coordinator | Routes work, enforces handoffs and reviewer gates. |

## Members

| Name | Role | Charter | Status |
|------|------|---------|--------|
| Da Vinci | Lead / Solution Architect | .squad/agents/davinci/charter.md | 🏗️ Lead |
| Tesla | Backend / Plugin Dev | .squad/agents/tesla/charter.md | 🔧 Backend |
| Edison | Power Platform / Data Dev | .squad/agents/edison/charter.md | 📊 Data |
| Bell | Integration Dev | .squad/agents/bell/charter.md | 🔌 Integration |
| Curie | Tester / QA | .squad/agents/curie/charter.md | 🧪 Tester |
| Scribe | Session Logger & Memory | .squad/agents/scribe/charter.md | 📋 Scribe |
| Ralph | Work Monitor | .squad/agents/ralph/charter.md | 🔄 Monitor |
| Rai | RAI Reviewer | .squad/agents/Rai/charter.md | 🛡️ RAI |
| Fact Checker | Verification & Devil's Advocate | .squad/agents/fact-checker/charter.md | 🔍 Verifier |

## Coding Agent

<!-- copilot-auto-assign: false -->

| Name | Role | Charter | Status |
|------|------|---------|--------|
| @copilot | Coding Agent | — | 🤖 Coding Agent |

### Capabilities

**🟢 Good fit — auto-route when enabled:**
- Bug fixes with clear reproduction steps
- Test coverage (adding missing tests, fixing flaky tests)
- Lint/format fixes and code style cleanup
- Dependency updates and version bumps
- Small isolated features with clear specs
- Boilerplate/scaffolding generation
- Documentation fixes and README updates

**🟡 Needs review — route to @copilot but flag for squad member PR review:**
- Medium features with clear specs and acceptance criteria
- Refactoring with existing test coverage
- API endpoint additions following established patterns
- Migration scripts with well-defined schemas

**🔴 Not suitable — route to squad member instead:**
- Architecture decisions and system design
- Multi-system integration requiring coordination
- Ambiguous requirements needing clarification
- Security-critical changes (auth, encryption, access control)
- Performance-critical paths requiring benchmarking
- Changes requiring cross-team discussion

## Project Context

- **Project:** power-notify — a Microsoft Power Platform / Dataverse notification engine
- **Owner:** Devon Aleshire
- **Stack:** Dataverse solution (PowerNotifyCore), C# plugins, pnfy_* entities, CSV-driven schema (schema/pnfy-*.csv) via build/Build-PnfySchema.ps1, solution ALM
- **Casting universe:** Famous Artists and Inventors (user-requested)
- **Created:** 2026-08-12
