# memory-router Python CLI - Plan 13: `learning_lifecycle_json` + `learning_usefulness_json`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the two LEARNINGS-derived summaries: `learning_lifecycle_json` (Bash 599-651) - current rows split into used/unused (by MEMORY-USAGE.json presence) plus stale_candidates - and `learning_usefulness_json` (Bash 653-712) - exclusive hot/warm/cold/stale tiers plus promote/compress candidates. Both need a `date_days_ago` clock helper. Consumed later by `status_json` and `curate`.

**Architecture:** Add `date_days_ago` to `hooks/memory_router/clock.py`. Extend `hooks/memory_router/summaries.py` with shared helpers (`_learning_stale_after`, `_usage_items`, `_current_rows`, `_learning_id`, `_bounded_ids`) and the two functions. Each returns a Python **dict** (serialized at the `contracts.dumps` boundary later). No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `datetime`); no new deps.

## Global Constraints

- **Drop-in / scope:** changes exactly: `clock.py` (add `date_days_ago` + `timedelta` import), `summaries.py` (add `clock` import + helpers + two functions), new `tests/test_clock.py`, `tests/test_summaries.py` (extend), one spec §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash `learning_lifecycle_json` (599-651), `learning_usefulness_json` (653-712), `date_days_ago` (173-182) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (bash normalized via `jq -c .`) across the reachable scenario set - see Self-Review.
- **`date_days_ago(days)`:** `today_utc - days` via `datetime` (`date -u -v-Nd` / `-d "N days ago"` are equivalent); non-numeric -> `""` (Bash `else printf ''`). `cutoff_date` is the date string, or `null` when `""`.
- **`_learning_stale_after`:** `${KIMIFLOW_LEARNING_STALE_AFTER_DAYS:-90}` then `case ''|*[!0-9]* -> 90`; honored only when non-empty all-ASCII-digit (`"0"` valid).
- **`_usage_items`:** Bash loads `.items // {}` only when the usage file exists and `jq -e .` passes (valid + truthy). Port: `{}` for missing/invalid/null/false; and (more robustly) `{}` for a valid non-object top level or a non-object `.items` - Bash errors there, but `MEMORY-USAGE.json` is always an object of objects, so unreachable.
- **Staleness (`_last_verified_is_stale`):** `cutoff != "" and (.last_verified // "") < cutoff`. After `// ""`, null/false are `""` (codepoint string compare; Python `str <` matches jq; a **missing** `last_verified` is therefore stale). A **non-string** `last_verified` is compared in jq's total order: bool/number sort BELOW strings (stale), array/object ABOVE (not stale). The helper replicates that instead of a raw Python `<`, which would `TypeError` on a parseable number/bool/array/object row (a latent crash caught in review; jq emits output there, so the port must not crash).
- **lifecycle used/unused:** jq `($usage["learning:" + id] // null) != null` -> present-and-not-null/false = used, else unused. `ids` filtered to `length>0`; `stale_candidate_ids` are NOT length-filtered (map `.id // ""`). Caps: `unused_current_ids[:20]`, `cold_candidate_ids[:10]`, `used_current_ids[:20]`. **Absent shape (missing learnings) omits the three `*_ids` keys.**
- **usefulness tiers (exclusive):** `stale` = is_stale; `hot`/`warm`/`cold` = NOT stale and `use_count >= 2` / `== 1` / `== 0`. `use_count = (usage["learning:"+id].use_count // 0) | tonumber? // 0` (`_n`). `promote` = `(hot + warm)` filtered by `confidence` (default `medium`) in `{high,medium}` AND `sensitivity` (default `normal`) NOT in `{private,security}`. `compress` = `cold + stale` (order preserved). `_bounded_ids` = non-empty ids `[:20]`. **Absent shape omits `basis`.**
- **Divergence (spec §12, unreachable):** a valid non-object `usage` top level, or a `false`/number/array usage-ENTRY (jq errors on `false.use_count`), makes Bash emit empty output; the port returns a valid result (usage treated as `{}` / use_count 0). Same class as the `usage_summary_json` row; `MEMORY-USAGE.json` is always an object of item-objects.
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/clock.py` | add `timedelta` import + `date_days_ago`. |
| `hooks/memory_router/summaries.py` | add `clock` import, `_learning_stale_after`, `_usage_items`, `_current_rows`, `_learning_id`, `_last_verified_is_stale`, `learning_lifecycle_json`, `_bounded_ids`, `learning_usefulness_json`. |
| `hooks/memory_router/tests/test_clock.py` | NEW: `DateDaysAgoCase`. |
| `hooks/memory_router/tests/test_summaries.py` | add `_LearningCase`, `LearningLifecycleCase`, `LearningUsefulnessCase`. |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (non-object usage). |

---

### Task 1: `date_days_ago` + the two learning summaries

**Step 1 (Red -> Green):** Implement exactly as shipped. Add `DateDaysAgoCase` and the two learning test cases (use far-past `2000-01-01` = always stale and far-future `2999-12-31` = always fresh to keep tests date-independent).

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (231 with this plan).
- Grounding harnesses: extract Bash `date_days_ago` (173-182) + each function into standalone scripts piped through `jq -c .`; drive both bash and Python over the scenario set under matched `KIMIFLOW_LEARNING_STALE_AFTER_DAYS`; diff -> identical for all reachable inputs.
- ASCII check on `clock.py` + `summaries.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (normalized via `jq -c .`) for both functions across: missing/empty learnings; mixed current/archived/superseded with used/unused/stale; missing `last_verified` -> stale; `last_verified == cutoff` boundary (not stale, strict `<`); explicit hot/warm/cold/stale tiers with stale-precedence; promote filtered by confidence (high/medium/low/default) and sensitivity (private/security/normal/default); compress = cold+stale; id capping (>20 unused, >10 cold; >20 usefulness); duplicate + missing ids; `use_count` as int/string/float (tonumber); null/false usage entries; malformed learnings lines; and `KIMIFLOW_LEARNING_STALE_AFTER_DAYS` overrides (30/0/abc/empty/9999). All identical. The only DIFFs were the unreachable non-object-`usage` cases noted in §12 (Bash errors -> empty; port stays robust).

**Review-driven fix:** the independent review (senior-reviewer) flagged a real P2 - a non-string `last_verified` (number/bool/array/object) made the port `TypeError` on `<`, while jq compares cross-type and emits output. Fixed via `_last_verified_is_stale` (jq total order) and re-grounded byte-for-byte across number/bool/false/null/array/object/string `last_verified` (`[123]->stale`, `[]->not stale`, etc.); +2 regression tests. The analogous cross-type-sort robustness of `_max_present` (committed Plans 10-12, date fields) is left as a carry-forward minor for the cutover review (out of Plan 13 scope).
