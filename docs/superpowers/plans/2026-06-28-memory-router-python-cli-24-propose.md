# memory-router Python CLI - Plan 24: `propose` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_propose` (Bash 3822-3929) - the learning-proposal lifecycle (preview / approve / reject / apply). The biggest single subcommand: ~11 helpers + approve/reject/apply state mutations to `PROPOSALS.jsonl`, `PENDING-PROPOSALS.md`, `STANDARDS.md`, `DECISIONS.md`, and `SKILL-DRAFTS/`. Reuses `evidence_fingerprints_json` (rows.py), `store.read_jsonl` (=jsonl_rows), `clock.iso_now`/`date_now`, `paths.rel_path`.

**Architecture:** New module `hooks/memory_router/propose.py` with `run(argv)` + all helpers below. Registered in `__main__.COMMANDS`.

**Tech Stack:** Python 3.9+ stdlib only (`os`). No new deps.

## Global Constraints

- **Drop-in / scope:** new `propose.py`, `tests/test_propose.py`; `__main__.py` += `"propose": propose.run`. No edits to `hooks/memory-router.sh`, manifests. §12 row(s) for the atomic writers vs Bash `>`-redirect (generalizes curate).
- **Source of truth:** Bash 3555-3929 @ `kimiflow--v0.1.50`. Ground byte-for-byte (whole real Bash vs Python CLI, isolated `env -i`).
- **Reused-helper note:** `evidence_fingerprints_json(root, evidence)` returns a list; comparisons use compact-JSON strings (`contracts.dumps`) - same as verify-run's freshness check.

### Helpers (faithful ports; jq line refs)
- **`current_evidence_backed_rows(learnings)`** (3555): `store.read_jsonl` -> keep `(.status//"current")=="current"` AND `(.sensitivity//"normal")!="security"` AND `len(.evidence//[])>0` AND NOT any evidence elem `== "NOT VERIFIED" or == "OUTSIDE_REPO"`.
- **`proposal_candidates_json(rows, state, now)`** (3565): keep rows with kind in `{project_rule_confirmed, important_decision, learned, trap_or_pitfall}`; per row: `id=.id//""`; `prev =` LAST state row with `(.id//"")==id` (else `{}`); `type = standard|decision|skill` (project_rule_confirmed->standard, important_decision->decision, else skill); `target_path = .kimiflow/STANDARDS.md | .kimiflow/DECISIONS.md | .kimiflow/project/PENDING-PROPOSALS.md`; object `{id, learning_id:id, type, kind:.kind//"learning", target_path, summary:.summary//"", evidence:.evidence//[], evidence_fingerprints:.evidence_fingerprints//[], status:prev.status//"pending", reason:prev.reason//"", created_at:prev.created_at//now, updated_at:prev.updated_at//now}` + conditionally add `applied_at`/`apply_note`/`skill_draft_path` when the prev value has length>0 (jq `+` append order).
- **`proposal_freshness_failures_json(root, proposals)`** (3612): per proposal, `stored=.evidence_fingerprints//[]`; empty -> `{id, "missing_evidence_fingerprints"}`; else compare compact-JSON to `evidence_fingerprints_json(root, .evidence//[])` -> `{id, "evidence_changed_or_missing"}`; collect in order.
- **`mark_proposals_need_revalidation(proposals, failures, now)`** (3639): for proposals whose id is in failures, set `status:"needs_revalidation", reason:(failure reason for that id, last-wins via from_entries), updated_at:now`.
- **`proposal_counts_json(proposals)`** (3658): `{total, pending:(status//"pending"=="pending"), approved, applied, rejected, needs_revalidation, by_type:(reduce -> {type: count})}`.
- **`proposal_notification_json(proposals)`** (3671): `{kind:"learning_proposals", path, state_path, pending, approved, applied, rejected, needs_revalidation, message: "Learning proposals: N pending, N approved, N applied, N rejected, N need revalidation."}` (counts as int->tostring).
- **`write_proposals_state(path, proposals)`** (3699): mkdir parent; write each compact (`jq -c '.[]'`) one per line. `store.atomic_write` (vs Bash `>` redirect; §12).
- **`write_proposals_markdown(path, proposals)`** (3705): the exact header + Commands block + 3 sections (Standards/Decision/Skill candidates), each `"No candidates."` when empty else `- [<status//pending>] <summary//""> (id: <id//"">; evidence: <evidence join ", ">)` (+ `; draft: <skill_draft_path>` for skill when present). `Generated: <iso_now>`. `store.atomic_write`.
- **`append_project_line(file, title, summary, line)`** (3734): mkdir parent; if file absent write `# <title>\n\n`; if `summary` already substring-present (`grep -Fq`) return False (no append); else append `line + "\n"` and return True.
- **`write_skill_draft(root, prop)`** (3746): write `SKILL-DRAFTS/<id>.md` (fixed template, `iso_now`), return `rel_path(root, draft_file)`.
- **`apply_approved_proposals(root, proposals)`** (3772): iterate proposals with `status=="approved"`; standard -> `append_project_line(STANDARDS.md, "Kimiflow Standards", summary, "- <summary> (evidence: <ev>; learning: <id>)")` (++appended_standards on True) + applied_ids+=id; decision -> `append_project_line(DECISIONS.md, "Kimiflow Decisions", summary, "- <date_now>: <summary> (evidence: <ev>; learning: <id>)")` (++appended_decisions) + applied_ids+=id; else -> `write_skill_draft` + manual_ids+=id + skill_drafts+={id,path}. Return `{applied_ids, manual_ids, skill_drafts, appended:{standards, decisions}}`.

### `run(argv)` (cmd_propose 3822-3929)
- Args: `--root`; `--write`(write=1); `--approve <id>`(append id to approve_ids, write=1); `--reject <id>`(append to reject_ids, write=1); `--reason <text>`; `--apply`(apply=1, write=1); `--pretty`; `--help`/`-h`; unknown->`die("propose: unknown argument: <a>", 2)`.
- `root=resolve_root`; `rows=current_evidence_backed_rows(LEARNINGS.jsonl)`; `state=store.read_jsonl(PROPOSALS.jsonl)`; `now=iso_now()`; `proposals=proposal_candidates_json(rows, state, now)`.
- **Unknown-id gate (DEAD CODE - OMITTED):** Bash 3851-3854 looks like an unknown-id gate but never fires (`($known | index(.))` rebinds `.` to `$known` -> subarray-self-search -> always `0` -> `missing` always `[]`). The port OMITS it; an unknown approve/reject id is silently accepted (written, nothing matches it). spec 12 row. [Found by grounding, NOT the original plan.]
- **Approve:** if approve_ids: `freshness_failures = proposal_freshness_failures_json(root, [proposals matching approve_ids])`; if any -> `mark_proposals_need_revalidation` + `write_proposals_state` + `write_proposals_markdown` + `die("propose: evidence stale; refresh learning review before approval: <csv>", 1)`; else set matched -> `{status:"approved", reason:"", updated_at:now}`.
- **Reject:** if reject_ids: set matched -> `{status:"rejected", reason:<reason>, updated_at:now}`.
- **Apply:** `apply_result` default `{"applied_ids":[],"manual_ids":[],"appended":{"standards":0,"decisions":0}}`; if apply: freshness over `[approved proposals]`; if any -> mark+write+`die(... "before apply: <csv>", 1)`; else `apply_result=apply_approved_proposals(root, proposals)`; then update proposals: applied_ids -> `{status:"applied", applied_at:now, updated_at:now}`, manual_ids -> `{status:"approved", apply_note:"skill_draft_review", skill_draft_path:<draft path>, updated_at:now}`.
- **Write:** if write: `write_proposals_state` + `write_proposals_markdown`.
- **Output:** `counts=proposal_counts_json(proposals)`; `notification=proposal_notification_json(proposals)`; `{schema_version:1, status:("applied" if apply else "written" if write else "preview"), path, state_path, written:(write==1), proposals:counts, apply_result, notification}`. `json_print(out, pretty)`.
- **Order-sensitive nuances:** the `die` paths on stale evidence WRITE state+markdown first (with the needs_revalidation marks) then exit 1. The markdown/state on a normal write reflect post-approve/reject/apply proposals.

- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/propose.py` | NEW: `run` + all 11 helpers. |
| `hooks/memory_router/__main__.py` | register `"propose": propose.run`. |
| `hooks/memory_router/tests/test_propose.py` | NEW: helper unit cases + `ProposeRunCase` + `ProposeParityCase` (preview / approve / reject / apply / stale-gate, stdout + written PROPOSALS.jsonl/PENDING-PROPOSALS.md/STANDARDS.md/DECISIONS.md vs pinned bash). |

---

### Task 1: propose

**Step 1 (Red -> Green):** Implement `propose.py` + tests + dispatch.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green.
- Grounding (isolated `env -i`): `bash <pinned> propose ...` vs `python3 -m memory_router propose ...` on a LEARNINGS.jsonl with proposal-kind, evidence-backed rows (+ a security/no-evidence/NOT-VERIFIED row that must be excluded): stdout identical for preview / `--approve <id>` / `--reject <id> --reason x` / `--apply` / unknown-id (exit 2) / stale-evidence approve+apply (exit 1); on writes verify PROPOSALS.jsonl, PENDING-PROPOSALS.md (timestamp-normalized), STANDARDS.md, DECISIONS.md, and SKILL-DRAFTS/<id>.md byte-identical. Use a recorder-written learning (append_learning_row) so fingerprints are real.
- ASCII check on `propose.py` -> clean.

## Self-Review (grounding evidence)

**Pre-implementation plan-audit** (external vs pinned Bash): 0 BLOCKER/HIGH/MEDIUM across all 12 functions; 1 LOW (plan prose listed the `Generated:` line last) -> the implementation already emits it as the 2nd line.

**Grounding findings (load-bearing, both caught by byte-for-byte grounding, NOT review):**
1. The **unknown-id gate is dead code** (jq `.`-rebinding `($known | index(.))` = subarray-self-search -> always 0 -> never fires). Bash silently accepts an unknown `--approve`/`--reject` id. The port omits the gate to match (an exit-2 would diverge). spec 12 row.
2. The initial fixture used `append_learning_row`, which sanitizes evidence to `NOT VERIFIED` in a non-git temp dir -> `current_evidence_backed_rows` excluded the rows. Fixed by hand-crafting `LEARNINGS.jsonl` with literal evidence + `evidence_fingerprints_json`-computed fingerprints (so freshness passes).

**Grounded byte-for-byte vs the real Bash** (isolated `env -i`): `ProposeParityCase` -> stdout+stderr+exit identical for preview / `--pretty` / `--approve` / `--reject --reason` / stale-evidence approve (exit 1) / unknown id (exit 0/written); the written `PROPOSALS.jsonl`, `PENDING-PROPOSALS.md`, `STANDARDS.md`, `DECISIONS.md`, and `SKILL-DRAFTS/<id>.md` byte-identical after timestamp/date normalization (full approve+apply chain).

**Independent senior-review** (vs Bash): 0 BLOCKER/HIGH, no issues. Confirmed the dead-gate omission is correct + that approve/reject matching still works for valid ids; the freshness compact-JSON compare is faithful (identical fingerprint key order); the markdown byte layout (Generated line 2, jq -r trailing newline per section, `; draft:` skill-only, "No candidates."); `append_project_line` re-reads disk per call (matches grep dedup); no `rows` shadowing (helper imported by name); `_merge` preserves jq `+` order with no mutation-aliasing.

**Suite:** 399 -> 415 tests, all green. ASCII-clean on `propose.py` + tests.
