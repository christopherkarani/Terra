# Terra Agent Instructions

## Public Repository Hygiene

This repository is the public-facing Terra SDK surface. Keep tracked files limited
to source, tests, examples, release notes, build scripts, and source-backed user
documentation.

Do not add or track:

- `tasks/`, `Plans/`, `Artifacts/`, or other task ledgers and planning scratchpads.
- `.agents/`, `.claude/`, `.codex/`, `.gemini/`, `.tmp/`, or local agent skills.
- Historical audit reports, discrepancy reports, readiness scorecards, internal
  source maps, or multi-agent review logs under `Docs/`.
- Marketing drafts, pitch material, founder/application text, investor notes,
  pilot targeting lists, or go-to-market plans.
- Roadmaps or implementation plans unless they are deliberately product-facing
  and approved as public documentation.

If an audit or planning artifact is needed during work, keep it untracked or in a
private workspace. If a durable public artifact is needed, rewrite it as
source-backed documentation for SDK users and remove internal process details.

## Documentation Rules

- Treat current source, tests, examples, and `Docs/PUBLIC-API-COVERAGE.md` as the
  public documentation baseline.
- Do not preserve stale audit files as public docs just because they contain useful
  notes. Fold only verified facts into canonical docs.
- Public docs should teach users how to install, configure, validate, and use the
  SDK. They should not expose agent workflow, private planning, or internal review
  history.

## Before Committing

- Run `git status --short` and confirm no internal planning or agent directories
  are tracked.
- Search new docs for private/internal wording before publishing:
  `rg -n -i "founder|investor|pitch|fundraise|go-to-market|target account|audit|scorecard|todo|lesson|internal planning" Docs README.md website Sources`.
- If a file is useful only to agents, do not commit it to this public repo.
