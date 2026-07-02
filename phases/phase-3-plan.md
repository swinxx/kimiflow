<!-- kimiflow:phase-detail source=docs/render/kimiflow/canonical/SKILL.md -->

## ⚫ Phase 3 — Plan (testable acceptance criteria)

Delegate to a `general-purpose` planner (or the read-only `Plan` agent + you persist). Inputs: `INTENT.md`+`RESEARCH.md` (or `PROBLEM.md`+`DIAGNOSIS.md`) + project memory. Pass the planner the `${CLAUDE_SKILL_DIR}/reference.md` path + the section names to read (acceptance-criteria template, code mandate) — not verbatim.

**(large) Dual-plan, selection-first:** TWO independent planners in parallel with distinct framings (minimal-first vs risk-first), one cross-family when available (→ reference.md "Model routing (per-role)"); each returns a complete plan skeleton + AC draft. Pick the stronger plan whole; adopt at most isolated, self-contained elements from the loser (a missing AC, a named risk) — never structural merges. The losing approach + selecting trade-off go under "Considered alternatives". `small`/`trivial`: single planner.

- `PLAN.md`: minimal, aligned with the existing architecture (and project standards); task breakdown; mark each task independent (file-disjoint) or dependent; anchored in `RESEARCH.md`/`DIAGNOSIS.md` (named patterns / verified root cause); no assumption without evidence. For parallel/worktree tasks add a `Consumes:`/`Produces:` interface block (→ reference.md).
- `PLAN.md` must be deterministic enough that two implementers can produce the same behavioral result: declare affected files/paths (or explicit new files), map every task to at least one `AC-N`, and keep unresolved markers (`TBD`, `TODO`, `NEEDS CLARIFICATION`, `NOT VERIFIED`, `UNKNOWN`) out of plan/acceptance. If a blocker remains, return to Phase 1/2; do not send it to reviewers.
- `ACCEPTANCE.md`: each criterion per template (EARS + concrete input→output + named verification method) with an explicit `AC-N → test_name` link. Lint criteria for vague terms ("fast", "robust") and missing error/edge cases. Trace each to `INTENT.md`/`PROBLEM.md`. In fix mode the central criterion = "the reproduction no longer fails" + no regression.
- **(large) Considered alternatives:** produced by the dual-plan selection — record the losing approach + the selecting trade-off in `PLAN.md` (→ reference.md "Understand & research"). small/trivial skip.
