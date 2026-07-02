# R4 Exit Audit

Date: 2026-07-02

Scope: exit audit for `docs/superpowers/plans/2026-07-02-rebuild-program.md` after the R2 prose inversion, R3 render hardening, and R4 budget checks.

## Verdict

Exit gate is open for the original rebuild program.

The remaining R2 prose-inversion gap was closed after the earlier audit. Mechanical gates are green, and the
confirmed R4 implementation bugs found by the exit audit were fixed:

- Render drift check now uses `kimiflow_core.render --check` and does not overwrite manual output drift.
- Launcher default/pretty output budgets are asserted in `hooks/test-launcher-status.sh`.
- `release-consistency-check.sh` enforces a 15,000-byte root `SKILL.md` ceiling, a 15,000-byte Codex skill ceiling, `phases/*.md` ceilings, and launcher output ceilings.
- Python-ported helpers now carry their R2 invariant targets in the production Python modules instead of Bash shim comments.
- Render sources are named as canonical workflow plus Codex host overlay.
- `SKILL.md` is now a thin driver at 13,084 bytes; `skills/kimiflow/SKILL.md` is 13,368 bytes.
- Phase detail is populated in `phases/phase-0-setup.md` through `phases/phase-7-review-commit.md`, with post-R2 phase-read enforcement carried by `hooks/active-run.sh` and the phase gates.
- Expanded scaling-knob prose moved to `docs/kimiflow-scaling-knobs.md`; `reference.md` remains the broad reference authority, not an always-loaded instruction burden.
- The invariant target map now points the moved phase rules at their phase files and retains runtime verification through `hooks/test-active-run.sh` and `hooks/kimiflow_core/tests/test_phase_reads.py`.

## Evidence

- `bash docs/superpowers/plans/2026-07-02-invariant-check.sh` -> `INVARIANTS OK`
- `bash hooks/release-consistency-check.sh` -> all version/render/budget checks consistent
- `bash hooks/test-release-consistency-check.sh` -> includes unstaged render-drift and phase-budget regressions
- `bash hooks/test-launcher-status.sh` -> includes default/pretty byte budget checks
- Full hook loop excluding production hooks reports `hook test failures: 0`
