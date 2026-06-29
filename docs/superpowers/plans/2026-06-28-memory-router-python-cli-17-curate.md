# memory-router Python CLI - Plan 17: `curate` subcommand (MEMORY-INDEX.json writer)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_curate` (Bash 4030-4113) - the first WRITE-path subcommand. It composes `status_json` + the raw summary aggregators + a topics map into the `MEMORY-INDEX.json` object, and on `--write` writes that file (pretty) and rebuilds the recall index via `cmd_index --write`. Includes the small `repo_id` helper (3545-3553). This introduces the first file-parity harness.

**Architecture:** New module `hooks/memory_router/curate.py` with `curate_json(root)`, `_topics`, `repo_id`, `run(argv)`. Reuses `status.status_json`, `summaries.*`, `text.word_count_file`, `clock.iso_now`, `index.run`, `store.atomic_write`, `contracts`. Registered in `__main__.COMMANDS`.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `re`, `subprocess`, `io`, `contextlib`); no new deps.

## Global Constraints

- **Drop-in / scope:** new `curate.py`, `__main__.py` dispatch entry, new `tests/test_curate.py`, one spec §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests.
- **Source of truth:** Bash `cmd_curate` (4030-4113) + `repo_id` (3545-3553) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (whole real Bash script vs Python CLI, isolated `env -i`, dead detection port) - stdout AND the written file - see Self-Review.
- **MEMORY-INDEX.json object (key order + source):** schema_version; updated_at (`iso_now`); repo_id; language (`"de"`); always_on_memory_tokens_estimate (`word_count_file(MEMORY.md)`); vault (`status.vault`); provider (`status.provider`); learnings + user_profile (**RAW** `read_jsonl_summary`, NOT the status-decorated copies with present/path); usage (`usage_summary_json`); economics (`economics_summary_json`); lifecycle (`learning_lifecycle_json`); topics; curation (`status.curation`).
- **`_topics`:** current rows grouped by `.topic // "uncategorized"` (sorted, codepoint), value = the list of `.id` (null preserved when missing); missing learnings -> `{}`.
- **`repo_id`:** git `remote.origin.url` normalized via three subs (`^git@github.com:`->`github.com/`, `^https://`->``, `\.git$`->``); `"unknown"` with no remote.
- **`--write`:** `mkdir -p project`; write the **pretty** (`jq .` = 2-space indent + trailing newline) form to `MEMORY-INDEX.json`; then run `index --write` swallowing stdout/stderr + errors (Bash `>/dev/null 2>&1 || true`). The port uses `store.atomic_write` + `contracts.dumps(pretty=True)+"\n"`.
- **arg parsing:** `--root`/`--write`/`--pretty`/`--help`/`-h`/unknown->`die(... ,2)`; `need_jq` no-op; `resolve_root`; stdout `json_print(out, pretty)`.
- **Divergence (spec §12):** the index write uses `store.atomic_write` (atomic temp+rename, refuses to write THROUGH a symlink) where Bash `jq . > "$index"` is a plain truncating redirect that follows a symlink. Unreachable (the index is a regular file); the port is the safer behavior.
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/curate.py` | NEW: `repo_id`, `_topics`, `curate_json`, `run`. |
| `hooks/memory_router/__main__.py` | register `"curate": curate.run`. |
| `hooks/memory_router/tests/test_curate.py` | NEW: `CurateRunCase` + `CurateParityCase` (stdout + first file-parity). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (atomic index write). |

---

### Task 1: curate + repo_id + write path

**Step 1 (Red -> Green):** Implement `curate.py` + tests + dispatch exactly as shipped.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (283 with this plan).
- Grounding: run `bash <pinned> curate ...` vs `python3 -m memory_router curate ...` (isolated `env -i`, dead detection URL); compare stdout (compact + pretty) AND the written `MEMORY-INDEX.json` (normalizing only `updated_at`); confirm `RECALL.sqlite` is rebuilt with equal doc count; check `repo_id` with a real git remote.
- ASCII check on `curate.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (isolated `env -i`, dead detection port): stdout compact + pretty (empty + populated roots, `updated_at` normalized); `topics` = `{alpha:[L2], beta:[L1,L3], uncategorized:[L4]}` (current only, stable file order within a group, missing-topic -> uncategorized); the **written** `MEMORY-INDEX.json` byte-identical (including 2-space indentation + trailing newline, only `updated_at` differs); `RECALL.sqlite` rebuilt with equal doc count (3 == 3); `repo_id` for a real remote (`git@github.com:foo/bar.git` -> `github.com/foo/bar`) identical, and "unknown" without one. In-repo `CurateParityCase` exercises both stdout and the file write against the pinned bash.
