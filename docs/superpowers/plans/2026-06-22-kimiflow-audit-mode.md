# kimiflow Audit/Cleanup-Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a third kimiflow mode — `audit` (cleanup via the ponytail lens) — that finds over-engineered/dead code in a bounded target, presents tagged slices for approval, and executes them slice-by-slice with a per-slice verify gate.

**Architecture:** Pure prompt feature — edits to `SKILL.md` (mode routing + phase branches) and `reference.md` (the "Audit mode" section: slice format, tags, safety). No new runtime code. It REUSES, and therefore DEPENDS ON, two features from the prior batch: **A1** (pre-build summary gate — shows the slice list for approval) and **A3** (caller-verified deletion gate — the grep==0 core of every `delete` slice).

**Tech Stack:** markdown (skill + reference); `git log` (history-freshness signal, invoked inline by the orchestrator); `grep` (repo-wide caller verification). No new dependencies.

## Global Constraints

- **Execute the prior plan FIRST.** `docs/superpowers/plans/2026-06-22-kimiflow-prebuild-gate-and-phase-tasklist.md` (Tasks 1–7) must be done — this plan references A1 (Phase-4 summary gate) and A3 (caller-verified deletion) as existing. Do not start this plan until that one is merged.
- **Engine unchanged:** audit is a new execution line; it must not alter feature/fix, the quality gates, thresholds, or artifacts.
- **Bounded target, repo-wide greps:** the audit *analyzes* only the given target path; every caller-verification `grep` runs over the WHOLE repo (`src` + tests), never only the target.
- **Safety (verbatim):** caller-grep is a documented MINIMUM (dynamic/reflective refs are a blind spot); a deletion needs grep==0 AND survives adversarial "find a live caller" AND tests stay green; recently-touched zero-caller code is treated as WIP (git-history-freshness) → downgrade/skip; on any doubt, downgrade or skip — never delete on assumption.
- **Tags:** exactly `yagni` | `delete` | `shrink` | `stdlib`.
- **Commits:** stage explicit named paths only — never `git add -A`/`.`; no AI-attribution trailer. Never mix a bare `git add` with a standalone ` . ` token (e.g. `jq -e .`) in one shell line (the `commit-secret-gate` false-positives).
- **Style:** match the surrounding SKILL.md/reference.md prose (compacted, telegraphic, bold only on critical words).

---

### Task 1: Mode routing + trigger (`audit`) — SKILL.md

**Files:**
- Modify: `SKILL.md` (frontmatter `argument-hint`; Modes section; Phase 0 step 2)

**Interfaces:** none (prompt behavior).

- [ ] **Step 1: argument-hint adds `--audit`**

In `SKILL.md` frontmatter, change:

```
argument-hint: <feature-or-bug> [--fix] [--prepare] [--quiet|--verbose] [--set-verbosity <level>] [--settings]  ·  --resume <slug>
```

to:

```
argument-hint: <feature-or-bug> [--fix] [--audit <path>] [--prepare] [--quiet|--verbose] [--set-verbosity <level>] [--settings]  ·  --resume <slug>
```

- [ ] **Step 2: Modes section — add the audit bullet**

In the Modes section, after the `Feature or fix:` bullet, add:

```
- **Audit / cleanup mode:** kimiflow detects cleanup intent ("remove dead code", "over-engineering audit", "entschlacken", "clean up") and runs the **ponytail lens** over a **required target path**. Force with **`/kimiflow --audit <path>`**. Staged: it finds tagged slices, shows them for approval (the Phase-4 summary gate), then executes them one slice = one commit with a per-slice verify gate. → reference.md "Audit mode".
```

- [ ] **Step 3: Phase 0 step 2 — route audit**

In `SKILL.md` Phase 0, find step 2 (`**Mode routing — feature or fix.**`). Replace its first two sentences:

```
2. **Mode routing — feature or fix.** Detect: build/add/change → feature; crashes/error/bug/"doesn't work"/wrong behavior → fix. `--fix` forces it. In doubt, ask one simple question. Record in STATE. Fix mode branches only phases 1+2; from phase 3 on, `PROBLEM.md` ≙ `INTENT.md` and `DIAGNOSIS.md` ≙ `RESEARCH.md`.
```

with:

```
2. **Mode routing — feature, fix, or audit.** Detect: build/add/change → feature; crashes/error/bug/"doesn't work"/wrong behavior → fix; remove dead code / over-engineering / "clean up" / "entschlacken" → **audit** (requires a target path — ask for one if missing). `--fix` / `--audit <path>` force the mode. In doubt, ask one simple question. Record mode (+ audit target) in STATE. Fix mode branches only phases 1+2 (`PROBLEM.md` ≙ `INTENT.md`, `DIAGNOSIS.md` ≙ `RESEARCH.md`). **Audit mode** branches phases 1–7 — see reference.md "Audit mode"; it is always scope ≥ `small`.
```

- [ ] **Step 4: Verify**

Run: `grep -c "Audit / cleanup mode" SKILL.md` → 1. Run: `grep -c "audit <path>" SKILL.md` → ≥ 1. Confirm frontmatter still valid: `grep -c "argument-hint" SKILL.md` → 1.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md
git commit -m "feat: route audit/cleanup mode (--audit <path> + auto-detect)"
```

---

### Task 2: Audit phase branches — SKILL.md

**Files:**
- Modify: `SKILL.md` (Phase 1, Phase 2, Phase 4, Phase 7 — audit branches)

**Interfaces:**
- Consumes: A1 pre-build summary gate (Phase 4) and A3 caller-verified deletion (Phase 5/7) from the prior plan.

- [ ] **Step 1: Phase 1 — audit-scope branch**

In `SKILL.md` Phase 1, after the `Fix → problem clarification:` bullet, add:

```
- **Audit → scope clarification:** which paths, how aggressive, behavior-preserve constraints, do-NOT-touch hints, "what stays untouched" → write `AUDIT-INTENT.md` (plain language) → **gate** "Is this the right cleanup scope?" (OK to continue).
```

- [ ] **Step 2: Phase 2 — "find the fat" branch**

In `SKILL.md` Phase 2, after the `**Fix → understand & diagnose**` block (ends with the `DIAGNOSIS.md` synthesis line), add a new block:

```
**Audit → find the fat** (read-only, evidence-based):
2. **Survey the target** (`Explore` agent, input `AUDIT-INTENT.md`): map what exists and why. For each non-trivial item ask the **ponytail Rung-1** question — not "can we dedupe" but "should this exist at all".
3. **Tag findings** `yagni`/`delete`/`shrink`/`stdlib`, each with `path:line` + replacement + a **repo-wide pre-delete grep** (`grep -rn` over `src` + tests, must return 0 for `delete`) + a **git-history-freshness** note (`git log -1` on the symbol — recently-touched zero-caller = likely WIP → downgrade).
4. **Synthesis → `AUDIT.md`**: self-contained **slices** ranked biggest-cut-first, plus a **do-NOT-touch** list (looks removable, but earns its place + why). Structure: → reference.md "Audit mode". **Caller-grep is a MINIMUM** — dynamic/reflective refs are a blind spot, so tests + adversarial verification (phase 4) are the backstop.
```

- [ ] **Step 3: Phase 4 — dead-claim verification + slice approval**

In `SKILL.md` Phase 4, after step 1's lens descriptions (A and B), add a third lens line right before the `Each reviewer gives reasoning…` line:

```
   - **(audit) refute the cut:** for each `delete`/`yagni` slice, actively hunt a **live caller** (repo-wide, incl. dynamic dispatch / reflection / string-keyed lookup). A cut survives only if no reviewer finds one; any live caller → downgrade or move to do-NOT-touch. `shrink`/`stdlib` must preserve behavior (tests green before+after).
```

(The existing binary, fail-closed, blocker-aware gate then counts unresolved cuts mechanically. The Phase-4 pre-build summary gate (A1) presents the surviving slice list for the user's OK before phase 5.)

- [ ] **Step 4: Phase 7 — slice commits**

In `SKILL.md` Phase 7 step 3 (Commit-gate), after the `**(large)**` sentence, add:

```
**(audit)** execute one slice at a time: verify its repo-wide grep returns 0 (A3), apply the cut/shrink, run the slice's verify gate (grep-sweep → typecheck/build → tests green; `shrink`/`stdlib` green before+after), edit companion tests in lockstep, then commit **one slice = one reviewable diff = one commit**. Never batch slices into one commit.
```

- [ ] **Step 5: Verify**

Run: `grep -c "Audit → scope clarification" SKILL.md` → 1. Run: `grep -c "Audit → find the fat" SKILL.md` → 1. Run: `grep -c "refute the cut" SKILL.md` → 1. Run: `grep -c "one slice = one reviewable diff = one commit" SKILL.md` → 1.

- [ ] **Step 6: Commit**

```bash
git add SKILL.md
git commit -m "feat: audit-mode phase branches (scope, find-the-fat, dead-claim verify, slice commits)"
```

---

### Task 3: reference.md — "Audit mode (ponytail lens)" section

**Files:**
- Modify: `reference.md` (new section after "Fix mode")

**Interfaces:**
- Consumes: A3 ("Code mandate" deletion rule) + "Review rubric" (adversarial) — cross-referenced.

- [ ] **Step 1: Insert the section**

In `reference.md`, immediately after the `## Fix mode (diagnosis) (Phase 1–2)` section (before its trailing `---`'s next section `## Project memory & standards`), insert:

````
---

## Audit mode (ponytail lens) (Phase 1–7)

A third mode (beside feature/fix) to safely shrink over-engineered / dead code in a **bounded target**. **Staged:** find → report → approve → execute. **Engine unchanged**; reuses the deletion gate ("Code mandate"), adversarial reviewers ("Review rubric"), the Phase-4 summary gate, and atomic commits.

**Core rule (ponytail Rung-1):** for each item ask not "can we dedupe" but **"should this exist at all?"** — resolves to *delete* or *earns-its-place → simplify*. Every cut is **caller-verified at execution time**; on any doubt, downgrade or skip — never delete on assumption.

**Tags:** `yagni` (speculative architecture) · `delete` (dead, zero-caller) · `shrink` (dedupe, behavior preserved) · `stdlib` (hand-rolled → standard library, edge-cases preserved).

**Safety (non-negotiable):**
- **Caller-greps run repo-wide** (`src` + tests), never only the target — a symbol in the target can be called from anywhere.
- **Caller-grep is a MINIMUM:** dynamic dispatch / reflection / string-keyed lookup escape it → tests-green + a do-NOT-touch list + the Phase-4 "refute the cut" lens are the backstop.
- **Git-history-freshness:** weigh a zero-caller symbol by `git log` — recently touched = likely WIP (downgrade); import removed long ago = confidently dead.

**`AUDIT-INTENT.md` (Phase 1, plain language):** target paths · aggressiveness · behavior-preserve constraints · do-NOT-touch hints · what stays untouched.

**`AUDIT.md` (Phase 2) — self-contained slices, ranked biggest-cut-first:**
```
## Slice <n>: <scope>  (~−<x> lines)
**Scope:** <paths>
**ponytail lens (why each exists):** per item — delete | earns-its-place→simplify
**Findings (ranked):**
| tag | what to cut | replacement | path:line | repo-wide pre-delete grep (→ 0 / expected) | freshness |
**do-NOT-touch:** <symbol> — <why it stays despite the grep suspicion>
**Verify gate:** grep-sweep clean → typecheck/build → tests green (shrink/stdlib: green before+after)
**Companion edits:** <tests referencing cut code, edited in lockstep>
```

**Execution (Phase 5–7):** one slice at a time — verify grep==0 → apply → run the slice's verify gate → companion edits → **one slice = one commit**. Never batch slices. `--prepare` stops after Phase 4 with the approved `AUDIT.md`.
````

- [ ] **Step 2: Verify**

Run: `grep -c "Audit mode (ponytail lens)" reference.md` → 1. Run: `grep -c "Rung-1" reference.md` → 1. Run: `grep -nE "yagni|stdlib" reference.md | head` → matches present.

- [ ] **Step 3: Commit**

```bash
git add reference.md
git commit -m "docs: reference.md Audit mode section (slice format, tags, safety)"
```

---

### Task 4: Release (CHANGELOG + version bump)

**Files:**
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`

**Interfaces:** none. (Version = whatever is current +1 patch at execution time; this plan ships AFTER the prior batch's 0.1.3, so likely **0.1.4** — confirm the then-current version before bumping.)

- [ ] **Step 1: Bump both version fields**

In `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, bump `version` by one patch from the then-current value (e.g. `0.1.3` → `0.1.4`).

- [ ] **Step 2: CHANGELOG entry**

In `CHANGELOG.md`, after the intro line and before the latest `## 0.1.x`, insert (adjust the version to match Step 1):

```
## 0.1.4

### Added
- **Audit / cleanup mode** — a third mode (`/kimiflow --audit <path>` or auto-detected) that runs the
  ponytail lens over a bounded target: finds tagged slices (`yagni`/`delete`/`shrink`/`stdlib`) with
  repo-wide caller-greps and git-history-freshness, presents them for approval (Phase-4 summary gate),
  then executes one slice = one commit with a per-slice verify gate. Caller-grep is a documented
  MINIMUM; tests + do-NOT-touch + adversarial "refute the cut" verification are the backstop. Engine unchanged.
```

- [ ] **Step 3: Validate + commit**

```bash
jq empty .claude-plugin/plugin.json
jq empty .claude-plugin/marketplace.json
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json CHANGELOG.md
git commit -m "release: 0.1.4 (audit/cleanup mode)"
```

(Keep this `git add` line git-only — no `jq -e .` on the same line.)

---

## Self-Review

**1. Spec coverage** — each spec section maps to a task:
- Full third mode + trigger (`--audit`/auto-detect, target required) → Task 1. ✓
- Staged find→report→approve→execute · phase mapping (1 scope, 2 find-the-fat, 4 dead-claim+gate, 5–7 slices) → Task 2. ✓
- Tags, AUDIT.md/slice format, do-NOT-touch, repo-wide grep, freshness, MINIMUM caveat, verify gate → Task 3. ✓
- Reuse of A1/A3/reviewers/commits → Tasks 2 & 3 (references) + Global Constraints dependency. ✓
- CHANGELOG + version → Task 4. ✓
- Out-of-scope (whole-repo sweep, slice parallelization, AST tooling) → simply absent. ✓

**2. Placeholder scan** — no TBD/TODO; all insert blocks literal. The version number in Task 4 is intentionally "confirm then-current +1" because this ships after the prior batch — not a placeholder gap. ✓

**3. Consistency** — tags `yagni|delete|shrink|stdlib`, file names `AUDIT-INTENT.md`/`AUDIT.md`, "one slice = one commit", "repo-wide grep", "Rung-1", "refute the cut" identical across Tasks 1–4 and the SKILL.md/reference.md edits. Dependency on A1/A3 stated in Global Constraints. ✓

**4. Known non-mechanical parts** — audit mode is orchestrator-behavioral; the only *mechanical* enforcement is the reused A3 grep gate. No unit tests here (the prior batch tests A1/A3); audit behavior is verified by UAT. Acknowledged, not a gap.
