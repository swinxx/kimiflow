# Handoff — memory-router Bash→Python port (session 5, Plan 19 = recall)

**Date:** 2026-06-29 · **Repo:** kimiflow · **Branch:** `feat/memory-router-py-foundation`

Supersedes the session-4 handoff. Per-plan detail lives in the gitignored ledger `.superpowers/sdd/progress.md` (read it for exact nuances + commit SHAs). This handoff carries the verified state + roadmap forward.

---

## TL;DR

This session shipped **Plan 19 — the `recall` subcommand**, the biggest remaining read. Built, externally **plan-audited pre-implementation** (0 BLOCKER/HIGH), **grounded byte-for-byte** vs the pinned Bash (`kimiflow--v0.1.50`), **independently senior-reviewed** (0 BLOCKER/HIGH, no fidelity bugs), tested green, committed (2 commits).

- New `recall.py` — `cmd_recall` (1826-2019) + `terms_json_from_query` / `jsonl_hits` / `write_recall_markdown` / `recall_json_path_for` / `write_recall_json`.
- New `usage_metrics.py` — `update_usage_metrics` (1705-1769), **shared with the future `history`**.
- `recall_index.py` += `run_artifact_rows_json` / `run_artifact_hits_json` + `_RUN_ARTIFACT_NAMES` (= index set **+ STATE.md**, a grounded Bash 1668-vs-2619 divergence) + `_iter_run_artifacts(root, names=…)` param (default unchanged → `build_recall_index` untouched).
- `text.py` += `ascii_lower` (jq `ascii_downcase`, ASCII-only — never `str.lower()`).

**Wired subcommands:** `classify`, `index`, `status`, `curate`, `record`, **`recall`**. **Suite: 293 → 342 tests, all green** (incl. parity harnesses shelling to the pinned bash). Bash original **untouched** (no cutover yet).

Resume with **"weiter mit history"** (or the next subcommand).

---

## Git state (end of session 5)

| Ref | Meaning |
|---|---|
| `feat/memory-router-py-foundation` | HEAD = Plan-19 feat `ddffa7d` (docs `f42b36a`); **all additive, Bash untouched, nothing merged/pushed** |
| `kimiflow--v0.1.50` (tag) | the pinned Bash source-of-truth |

`git diff main HEAD -- hooks/memory-router.sh` is still empty. Working tree clean.

**Verify (re-run to confirm green):**
```bash
cd "<repo>" && export PATH="/opt/homebrew/bin:$PATH"
( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )   # 342 OK
git diff --stat main HEAD -- hooks/memory-router.sh                                  # empty
```

## Package state — `hooks/memory_router/`

Modules: `__init__`, `__main__`, `cli`, `contracts`, `store`, `paths`, `text`, `clock`, `classify`, `rows`, `writes`, `memory_md`, `recall_index`, `index`, `summaries`, `global_metrics`, `provider`, `status`, `curate`, `record`, **`recall`** (19), **`usage_metrics`** (19).

---

## What's NEXT — remaining subcommands, then cutover

Each is its own plan via the proven loop. Bash line ranges @ `kimiflow--v0.1.50`:

1. **`history`** — `cmd_history` (2021-2085). **Nearly all deps already ported this session.** Flow: args `--root/--query/--query-file/--max(default 10)/--write(boolean, NOT a path)/--pretty`; query-file → first 120 lines; `--max` digit-validated; with a query → `terms_json_from_query` + `run_artifact_hits_json`; without → `query="recent"`, `terms=[]`, `hits = run_artifact_rows_json | .[:max] | map(del(.text))`; `status` = `preview`→`written` on `--write`. JSON: `{schema_version,status,query,query_terms,path:".kimiflow/project/RUN-HISTORY.json",markdown_path:".kimiflow/project/RUN-HISTORY.md",written:(write==1),hits}`. On `--write`: `jq . > RUN-HISTORY.json` (pretty) + **NEW `write_history_markdown`** (1687-1703: `# Run History Recall`, Generated/Query/Hits, `## Hits` per-hit `- [slug · artifact] summary (path)`) + `update_usage_metrics(root, hits, "history")` (done). Only `write_history_markdown` is new.
2. **`metrics`** — `cmd_metrics` (2087+) incl `--global`/`--global-purge`: the global-metrics record/purge infra (`ensure_global_metrics_salt`/`hash_text`/project_id) on top of the `global_metrics.py` location helpers (Plan 12).
3. **`review-run`** + **`verify-run`** — run-artifact review/verify.
4. **`consolidate`** + **`propose`** — proposal lifecycle (`quality_gate_json` @ 2339; `memory_security_json` done).
5. **`provider`** subcommand — `cmd_provider` (4160+): status/health/setup/detect/connect/configure/prefetch/sync; needs `provider_setup_plan_json` (890-994), the markdown writers (`write_provider_prefetch_markdown`/`write_provider_sync_markdown` 4115-4158), base/mcp-url helpers.
6. **Cutover** (final, public — present to user for go/no-go): replace the Bash body with the shim `exec env PYTHONPATH="$dir" python3 -m memory_router "$@"`, delete the Bash, full suite + smokes green, update README/COMPATIBILITY (Python ≥3.9)/CHANGELOG, `/release`.

---

## The proven loop (unchanged; key reminders)

1. **Plan-audit (external, pre-impl):** an auditor checks the plan's behavioral claims vs the real Bash; fix BLOCKER/HIGH, re-audit (cap ~3); null open → build. This session it caught 5 LOW imprecisions worth folding in.
2. **Ground byte-for-byte** vs the pinned Bash before committing — extract whole script / per-fn via awk; normalize via `jq -c .`; diff. Highest-leverage step.
3. **Isolated env for provider/network/record/recall grounding:** host has a **real `OBSIDIAN_API_KEY`** + `KIMIFLOW_OBSIDIAN_MCP_AVAILABLE=1`. Always run grounding under `env -i PATH=… HOME=/tmp KIMIFLOW_OBSIDIAN_URL='http://127.0.0.1:9/'` (dead port) + a **test token only**. Never log/commit the real key.
4. **Independent senior-review** per block vs the Bash source.
5. **Pure ASCII** every changed *source* file (`[ (i+1,repr(l)) for i,l in enumerate(open(f)) if any(ord(c)>127 for c in l) ]`); middle-dot / accents as `\uXXXX`. (Markdown plan/spec docs keep the existing literal `§`/`·` convention.)
6. Commit named paths only; **no AI/co-author trailer**; never `git add -A`. `docs: plan N` = the plan doc; `feat(memory_router): …` = spec §12 + code + tests. Ledger `.superpowers/sdd/progress.md` is gitignored.

### Carry-forward minors (address at cutover review)
- `_jq_or` now has 5 copies (recall_index, summaries, provider, curate, recall + usage_metrics) — shared-helper consolidation overdue.
- Index parity in the recall harness is deliberately index-free (both `index_status:missing`) to dodge the bash-vs-stdlib build row-count diff (S15203); read-side index parity (`used`/`available_no_hits`) was grounded manually against a shared bash-built DB. The dedicated `recall_index` harness (Plans 6-7) owns FTS build parity.

## spec §12
Two new rows this session: recall `jsonl_hits`/`run_artifact_hits_json`/`update_usage_metrics` non-object-row skip (unreachable, safer); recall `--write` atomic writers + run-artifact `cut -c` codepoint slice (RECALL.md/.json atomic+symlink-safe, MEMORY-USAGE.json replicated mktemp+mv 0600). All unreachable-and-safer or replicated.

## Open decisions for the user
- **Merge `feat/memory-router-py-foundation` → `main`?** A large additive branch (Bash untouched). A whole-branch review before merge would be warranted; otherwise keep accumulating until cutover.
- **Push local `main`** (still has unpushed spec/Plan-0 commits) or leave local?
