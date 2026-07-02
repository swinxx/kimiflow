<!-- kimiflow:phase-detail source=docs/render/kimiflow/canonical/SKILL.md -->

## 🧭 Explore (opt-in, before Phase 1) — diverge on direction

Runs only on `--explore` or an accepted offer (→ reference.md "Explore phase"). **Feature only** — a fix/cleanup that surfaces → suggest `--fix`/`--audit`. Terse-output governs.

1. **Bound (≤1 question)** — one plain-language question only if the request lacks the goal/constraints to explore relevantly; else skip.
2. **Fan-out** — 2–3 read-only `Explore` agents, each forced to a DISTINCT direction, codebase-grounded (`file:line`; "NOT VERIFIED" if speculative). Each returns: framing · sketch · effort/risk · trade-off · rules-out.
3. **Menu** — synthesize 2–3 distinct directions (each ≤3 lines), write `EXPLORE.md`, show menu + path (bounded terse-output exemption).
4. **Pick (gate, human):** **continue** → chosen direction seeds Phase 1 `INTENT.md` → normal loop. **stop** → like `--prepare` (STOP, update STATE, emit `--resume`). **none** → ONE re-fan-out with the user's steer, then stop + ask. **headless / no answer** → never auto-pick; like `--prepare`. Set `Phase E (explore): done` in STATE with the chosen direction.

## 🔵 Phase 1 — Clarify (plain language): Intent (feature) or Problem (fix)

Goal: shared understanding BEFORE research/plan. kimiflow clarifies itself (embedded), always in plain language (everyday words, one question at a time with a recommended answer, WHAT/WHY not HOW, bounded ~5 questions or "ok"). Scope sets depth (trivial → skip only when exact/no ambiguity, small/quick → mandatory micro-grill with 2–3 targeted questions or explicit confirmation of recommended assumptions in the current run, large → full). Loose prior conversation informs the questions but never counts as confirmation. Full rules: → reference.md "Intent clarification" / "Fix mode".

- **Feature → intent clarification:** clarify goal, value, in/out of scope, "what done looks like" → write `INTENT.md` → **gate** "Does this match?" (OK to continue).
- **Fix → problem clarification:** symptom, expected vs. actual, when/how it occurs (steps, logs, since when, always/intermittent) → write `PROBLEM.md` → **gate** "Did I understand the problem correctly?" (OK to continue).
- **Audit → scope clarification:** which paths, how aggressive, behavior-preserve constraints, do-NOT-touch hints, "what stays untouched" → write `AUDIT-INTENT.md` (plain language) → **gate** "Is this the right cleanup scope?" (OK to continue).
- **Mechanical clarify gate:** before Phase 2, run `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR}/hooks/clarify-gate.sh .kimiflow/<slug>` (Codex: `KIMIFLOW_HOST=codex` and `KIMIFLOW_PLUGIN_ROOT`). `OPEN` is required. For phase-read runs, first record fresh Phase 0 and Phase 1 reads; this gate checks through Phase 1. For `small`/`quick`, the artifact must include `<!-- kimiflow:clarify-evidence mode=questions count=2 confirmed=yes source=current-run -->` after 2–3 answers, or `mode=assumptions count=3 confirmed=yes source=current-run` after confirmed recommended assumptions in this run. The Phase-4 plan-blocker rechecks this, so a skipped micro-grill or a loose-prior-chat "confirmation" cannot silently reach reviewers.
