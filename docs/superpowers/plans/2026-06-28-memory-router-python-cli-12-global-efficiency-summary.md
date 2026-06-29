# memory-router Python CLI - Plan 12: `global_efficiency_summary_json`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `global_efficiency_summary_json` (Bash 483-597, ~115 lines) - the last big economics pipeline, aggregating the cross-project, local-anonymous `~/.kimiflow/metrics/token-economics.jsonl`. Unlike `economics_summary_json` it does **not** recompute avoided/net or apply `tonumber` (the Bash `def n` at line 533 is dead code); it sums the stored fields directly and adds `enabled`/`scope`/`projects_tracked`/`privacy`/`last_recorded_day`. Needs the global-metrics location helpers (`global_metrics_enabled`/`base_dir`/`display_path`). Consumed later by `status_json`.

**Architecture:** New module `hooks/memory_router/global_metrics.py` (the three location/enablement helpers; grows when the `metrics --global` subcommand lands). Extend `hooks/memory_router/summaries.py` with `_jq_sum` (jq `[...]|add // 0` rendering), `_global_efficiency_absent`, `global_efficiency_summary_json`. Returns a Python **dict** (serialized at the `contracts.dumps` boundary later). No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `math`); no new deps.

## Global Constraints

- **Drop-in / scope:** changes exactly: new `global_metrics.py`, `summaries.py` (extend), new `tests/test_global_metrics.py`, `tests/test_summaries.py` (extend), one spec §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash `global_efficiency_summary_json` (483-597) + `global_metrics_enabled/base_dir/display_path` (366-385) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (key order + values, bash normalized via `jq -c .`) across 22 scenarios - see Self-Review.
- **`global_metrics.enabled()`:** `${KIMIFLOW_GLOBAL_METRICS:-on}`; only the exact spellings `off|OFF|0|false|FALSE|no|NO` disable it (anything else, incl `""`/unset, is on).
- **`global_metrics.base_dir()`:** `KIMIFLOW_HOME`, else `HOME/.kimiflow`; `None` (Bash `return 1`) when neither yields a base or the base is empty / `"/"`. File = `base_dir()/token-economics.jsonl`.
- **Absent shape:** when not enabled OR no base OR file missing. `enabled` reflects the flag; note is `"No global local efficiency rows recorded yet."` when enabled else `"Global local efficiency stats are disabled by KIMIFLOW_GLOBAL_METRICS."` Same key order as the present shape.
- **No normalization:** present sums use `_jq_or(field, 0)` (null/false/missing -> 0) and NO `tonumber`. Real token-count fields are always integers.
- **`_jq_sum` = jq `[ ... ] | add // 0`:** empty list -> `0`; a single element is returned verbatim (jq preserves a literal's form, `5.0` stays `5.0`); 2+ elements do real addition rendered canonically - an integral float result collapses to an int (`-5.5 + 2.5 -> -3`, not `-3.0`). Verified: `jq -cn '[5.0]|add'` = `5.0`, `[5.0,0]|add` = `5`, `[-5.5,2.5]|add` = `-3`, `[2.5,2.4]|add` = `4.9`.
- **`projects_tracked`:** jq `map(.project_id // empty) | unique | length` - null/false/missing dropped, distinct count.
- **Assessment (exact):** `confidence`: `0->none`, `<8->low`, `<20->medium`, else `high`. `verdict`: `0->no_data`, `<8->insufficient_data`, `net>0 and saving>=waste->saving_likely`, `waste>saving or net<0->waste_risk`, else `neutral`. `action_required`: `n>=8 and (waste>saving or net<0)`. `note`: 4 fixed strings on the same branches. `estimated_savings_percent`: `floor(net*100/avoided)` if `avoided>0` else `null`. `averages`: `floor(x/n)` if `n>0` else `0`. `saving`/`waste` counts key on `.result // ""`; `by_result` keys on `.result // "unknown"` in jq `reduce` first-appearance order.
- **`last_recorded_day`:** jq `[$rows[]?.recorded_day // empty] | sort | last // null` (drop null/false/missing, max, else null) = `_max_present`.
- **Missing vs empty:** missing file -> absent (`present:false`). An existing **empty** file goes through the row path: `present:true`, `runs_tracked:0`, `verdict:no_data`, `confidence:none`, note "Too few global local runs...".
- **Divergence (spec §12):** the single-element-verbatim vs computed-canonical float rendering is reachable only with float fields, which real token telemetry never has; `_jq_sum` matches jq byte-for-byte regardless, so this is replicated, not a divergence. (`economics_summary_json` Plan 11 leaves the analogous edge documented; not retouched here.)
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/global_metrics.py` | NEW: `enabled`, `base_dir`, `display_path`. |
| `hooks/memory_router/summaries.py` | add `_GLOBAL_EFFICIENCY_FILE`, `global_metrics` import, `_jq_sum`, `_global_efficiency_absent`, `global_efficiency_summary_json`. |
| `hooks/memory_router/tests/test_global_metrics.py` | NEW: `EnabledCase`, `BaseDirCase`, `DisplayPathCase`. |
| `hooks/memory_router/tests/test_summaries.py` | add `GlobalEfficiencySummaryCase`. |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | note the `_jq_sum` float rendering (replicated). |

---

### Task 1: `global_metrics` helpers + `global_efficiency_summary_json`

**Files:** New `global_metrics.py`; edit `summaries.py`, `tests/test_global_metrics.py` (new), `tests/test_summaries.py`.

**Step 1 (Red -> Green):** Implement `global_metrics.py` and the `summaries.py` additions exactly as shipped (see the committed source). Add `EnabledCase`/`BaseDirCase`/`DisplayPathCase` and `GlobalEfficiencySummaryCase`.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (216 with this plan).
- Grounding harness: extract Bash `global_metrics_*` (366-385) + `global_efficiency_summary_json` (483-597) into a standalone script piped through `jq -c .`, drive both bash and Python across the 22 scenarios under matched env (`KIMIFLOW_GLOBAL_METRICS`/`KIMIFLOW_HOME`/`HOME`); diff each -> identical.
- ASCII check on `summaries.py` + `global_metrics.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (normalized via `jq -c .`) across 22 scenarios: disabled; enabled-but-no-base (no HOME/KIMIFLOW_HOME); missing file; empty file (present n=0); mixed saving/waste/neutral/unknown with repeated + null + missing `project_id` and `recorded_day`; n=8 (medium/saving_likely boundary); n=20 (high); all-null/missing fields; malformed lines skipped; floats summing to an integral total (multi-element -> int) and a single-row float literal (preserved as float); and all 12 `KIMIFLOW_GLOBAL_METRICS` enable/disable spellings. All identical.
