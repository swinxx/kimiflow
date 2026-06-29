# memory-router Python CLI - Plan 19: `recall` subcommand

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port `cmd_recall` (Bash 1826-2019) - the biggest remaining read. It assembles the recall context object (always-on MEMORY/USER content within a token budget + LEARNINGS/FACTS substring hits + RECALL.sqlite FTS hits + run-artifact hits) with reason codes, and on `--write` emits `RECALL.md` + a sibling `.json` and updates `MEMORY-USAGE.json`. stdout is the JSON object (timestamp-free; nondeterminism lives only in the written files).

**Architecture:** New module `hooks/memory_router/recall.py` with `run(argv)` + `recall_json(root, query, max_hits)`. New module `hooks/memory_router/usage_metrics.py` with `update_usage_metrics(root, hits, event_kind)` (shared with the future `history` subcommand - Bash calls it from both). `recall_index.py` gains `run_artifact_rows_json`/`run_artifact_hits_json` (run-artifact source; sibling to the already-ported `_iter_run_artifacts`). `text.py` gains `ascii_lower` (jq `ascii_downcase` / `tr '[:upper:]'`, ASCII-only). Reuses: `recall_index.fts_hits_json`/`fts5_available`, `text.word_count_file`, `store`, `contracts`, `clock`, `paths`, `cli`.

**Tech Stack:** Python 3.9+ stdlib only (`io`, `os`, `re`, `json`). No new deps.

## Global Constraints

- **Drop-in / scope:** new `recall.py`, `usage_metrics.py`, `tests/test_recall.py`; edits to `recall_index.py` (add `run_artifact_rows_json`/`run_artifact_hits_json` + `_RUN_ARTIFACT_NAMES`; parametrize `_iter_run_artifacts(root, names=_ARTIFACT_NAMES)` - default preserves the index name set, so `build_recall_index` is unchanged), `text.py` (add `ascii_lower`), `__main__.py` (register `"recall"`). No edits to `hooks/memory-router.sh` or manifests.
- **Source of truth:** Bash `cmd_recall` (1826-2019), `terms_json_from_query` (1570-1589), `jsonl_hits` (1591-1622), `run_artifact_rows_json` (1624-1670), `run_artifact_hits_json` (1672-1685), `update_usage_metrics` (1705-1770), `write_recall_markdown` (1772-1794), `recall_json_path_for` (1796-1802), `write_recall_json` (1804-1808) @ `kimiflow--v0.1.50`. Ground byte-for-byte (whole real Bash vs Python CLI, isolated `env -i`, dead detection port).

### Arg parsing (`run`)
`--root`/`--query`/`--query-file`/`--max`(default `5`)/`--write`(takes a path value)/`--pretty`/`--help`/`-h`/unknown->`die("recall: unknown argument: <a>", 2)`. A value flag consumes the next token; trailing flag with no value -> `""`. Then: `need_jq` is a no-op (port); `root = resolve_root(root)`. If `--query-file`: file must exist else `die("query file not found: <f>", 2)`; `query = sed -n '1,120p'` of it (first 120 lines, trailing newlines stripped). Require non-empty `query` else `die("recall requires --query or --query-file", 2)`. `--max` must be **non-empty AND all ASCII digits** else `die("recall --max must be a number", 2)` (Bash `''|*[!0-9]*` rejects the empty string too - reachable via a trailing `--max`).

### `recall_json(root, query, max_hits)` -> dict (EXACT key order)
- `project=root/.kimiflow/project`; `memory=MEMORY.md`, `user_memory=USER.md`, `learnings=LEARNINGS.jsonl`, `facts=FACTS.jsonl`.
- `budget = int(KIMIFLOW_MEMORY_BUDGET or 900)`; `user_budget = int(KIMIFLOW_USER_MEMORY_BUDGET or 500)` (empty/unset -> default; non-int unreachable, Bash `-le` also needs int).
- `memory_tokens = word_count_file(memory)`; `user_tokens = word_count_file(user_memory)`.
- `terms = terms_json_from_query(query)`; `omitted = []`.
- **MEMORY gate:** file present & `tokens <= budget` -> status `included`, content = sed `1,160p`; present & over -> `omitted_over_budget`, content `""`, append `"MEMORY.md omitted: over budget"`; absent -> `missing`, content `""`, append `"MEMORY.md missing"`.
- **USER gate:** same with `user_budget`, sed `1,120p`, messages `"USER.md omitted: over budget"` / `"USER.md missing"`.
- `learning_hits = jsonl_hits(learnings, terms, max, "id,kind,scope,topic,summary,status,sensitivity,evidence")`.
- `fact_hits = jsonl_hits(facts, terms, max, "kind,area,path,summary,confidence")`.
- `index_hits = recall_index.fts_hits_json(root, terms, max)`.
- `history_hits = run_artifact_hits_json(root, terms, max)`.
- **`index_status` ladder:** `used` if `index_hits` nonempty; elif `RECALL.sqlite` file present -> `available_no_hits`; elif `fts5_available()` -> `missing`; else `unavailable`.
- Build dict: `schema_version:1, query, query_terms:terms, token_budget:budget, sources:{memory{path,status,tokens_estimate,content}, user_profile{path,status,tokens_estimate,budget:user_budget,content}, learnings{path,count,hits}, facts{path,count,hits}, index{path,status,count,hits}, history{path:".kimiflow/project/RUN-HISTORY.json", status:(used if hits else available_no_hits),count,hits}}, explanation:{reason_codes,included_sources,omitted_sources,hit_counts{learnings,facts,index,history,total}}, omitted}`. Reason codes / included / omitted_sources exactly per Bash 1967-2003 (order-sensitive list-comprehension of conditionals).

### `run` write path (only on `--write <path>`)
- Absolutize: if not starting `/` -> `write_path = root + "/" + write_path`.
- `write_recall_markdown(write_path, obj)` then `write_recall_json(recall_json_path_for(write_path), obj)`.
- `usage_hits = obj.sources.learnings.hits + obj.sources.index.hits + obj.sources.history.hits` (NOT facts); `update_usage_metrics(root, usage_hits, "recall")`.
- Always: `json_print(obj, pretty)`.

### Helpers (faithful ports)
- **`terms_json_from_query(query)`** -> list: `ascii_lower(query)` -> split on `[^a-z0-9_-]+` -> keep `len>=3` AND not in stopwords `{the,and,for,mit,und,der,die,das,ein,eine,ist,sind,was,wie,this,that,from,into,zur,zum,auf,von}` -> dedup keeping **first occurrence order** -> first 30. If empty -> `[ascii_lower(query)]`.
- **`jsonl_hits(file, terms, max, fields)`** -> list of full matching rows: missing file -> `[]`; else `store.read_jsonl` rows, keep `(.status // "current")=="current"`, keep `_hit(field_text(row, fields), terms)`, take first `max`. Non-dict rows skipped (safer; unreachable - §12 same class as usage rows). `field_text`: for each comma-split field, `v = row.get(f)`; `None`/`False -> ""`; list -> `" ".join` (null elem -> `""`); dict -> `contracts.dumps(v)` (jq `tostring` = compact JSON); else `str` (bool `True->"true"`). `_hit(text, terms)`: `t = ascii_lower(text)`; `any(term != "" and term in t for term in terms)`.
- **`run_artifact_rows_json(root)`** (recall_index.py): if no `.kimiflow` -> `[]`. Walk via `_iter_run_artifacts(root, _RUN_ARTIFACT_NAMES)` where `_RUN_ARTIFACT_NAMES = _ARTIFACT_NAMES | {"STATE.md"}` **(divergence vs build_recall_index, which omits STATE.md - grounded)**, sorted. Per file: `rel`, `slug=rel.split("/")[1]`, `artifact=rel split components 3+` (`"/".join(rel.split("/")[2:])`), `body=_first_lines(_read_body(full), 180)`, `summary` = first body line that after stripping ASCII whitespace is non-empty, not a `^#{1,6}` + ASCII-whitespace heading (use an explicit ASCII class `[ \t\r\f\v]`, NOT Python `\s` which is Unicode), not `^```` fence; internal ASCII-whitespace runs collapsed to single space; then first 420 chars (char-truncation, consistent with `slugify` `cut -c`). Row: `{kind:"run_artifact", slug, artifact, path:rel, ref:rel, title:slug+" "+MIDDOT+" "+artifact, summary, text:body}`.
- **`run_artifact_hits_json(root, terms, max)`** (recall_index.py): `run_artifact_rows_json` -> keep `_hit(slug+" "+artifact+" "+summary+" "+text, terms)` -> first `max` -> drop `text` key (order: kind,slug,artifact,path,ref,title,summary).
- **`update_usage_metrics(root, hits, event_kind)`** (usage_metrics.py): `mkdir -p project`; `now=iso_now()`; read `MEMORY-USAGE.json` via `store.read_json`, default `{schema_version:1, updated_at:None, items:{}, events:[]}` when missing/invalid/null/false/non-dict. `updates = [{key:hit_key(h), value:{kind:.kind//"memory", source:.source//.path//"", title:.title//.summary//.id//"", ref:.ref//((.evidence//[])|.[0]//""), summary:.summary//""}} for h]`. `hit_key`: `.id` nonempty -> `"learning:"+id`; elif `.kind=="run_artifact"` -> `"run:"+(.path//.ref//"unknown")`; else `(.kind//"memory")+":"+(.ref//.path//.title//"unknown")`. Then `schema_version=1; updated_at=now; items=(dict or {}); events=(list or [])`; for each update `items[key] = {**(items.get(key) or {} if dict else {}), **value, "use_count": (existing use_count or 0)+1, "last_used_at": now}` (use_count reads the **accumulating** items so repeated keys increment cumulatively; jq `+` key-order preserved). Append one event `{kind:event_kind, at:now, hit_count:len(updates), estimated_tokens: sum over updates of word-token count of the **normalized** `(value.title+" "+value.summary)` (NOT the raw hit fields - Bash 1761 reads `.value.*`) via `gsub("[^A-Za-z0-9_]+"," ")|split(" ")|select(len>0)|length` (use `_jq_sum`), keys: sorted-unique update keys}`; keep `events[-100:]`. Write **pretty** (jq default, 2-space + trailing `\n`) via `store.atomic_write(path, dumps(out, pretty=True)+"\n", mode=0o600, refuse_symlink=False)` - matches Bash `mktemp`(0600)+`mv`(replaces symlink target).
- **`write_recall_markdown(path, obj)`**: mkdir parent; emit the exact `# Recall` / `Generated: <iso_now>` / `Query:` / `Terms: <join ", ">` / `Token budget:` / `## Sources` (6 bullets: MEMORY.md, USER.md, LEARNINGS.jsonl hits, FACTS.jsonl hits, RECALL.sqlite `<status> (<count> hits)`, Run history hits) / `## Explanation` (Reason codes join ", ", Total hits `total//0`) / `## Omitted` (one `- <item>` line per omitted; none -> no lines) layout. `store.atomic_write`.
- **`recall_json_path_for(path)`**: `path[:-3]+".json"` when `path.endswith(".md")` else `path+".json"`.
- **`write_recall_json(path, obj)`**: mkdir parent; `store.atomic_write(path, dumps(obj, pretty=True)+"\n")` (jq `.` pretty + trailing newline).
- **`ascii_lower(s)`** (text.py): map only ASCII `A-Z`->`a-z` (jq `ascii_downcase` / C-locale `tr '[:upper:]'`); never `str.lower()` (non-ASCII untouched).

- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/recall.py` | NEW: `run`, `recall_json`, `terms_json_from_query`, `jsonl_hits` (+`_field_text`/`_hit`), `write_recall_markdown`, `recall_json_path_for`, `write_recall_json`, `_sed_read`. |
| `hooks/memory_router/usage_metrics.py` | NEW: `update_usage_metrics` (+`_hit_key`). |
| `hooks/memory_router/recall_index.py` | EDIT: `_RUN_ARTIFACT_NAMES`, `_iter_run_artifacts(root, names=...)`, `run_artifact_rows_json`, `run_artifact_hits_json`. |
| `hooks/memory_router/text.py` | EDIT: `ascii_lower`. |
| `hooks/memory_router/__main__.py` | register `"recall": recall.run`. |
| `hooks/memory_router/tests/test_recall.py` | NEW: `RecallRunCase` + `RecallParityCase` (stdout + written RECALL.md/.json + MEMORY-USAGE.json parity vs pinned bash, timestamps normalized). |

---

### Task 1: recall

**Step 1 (Red -> Green):** Implement the modules + tests + dispatch exactly as specified.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green.
- Grounding (isolated `env -i PATH=... HOME=/tmp KIMIFLOW_OBSIDIAN_URL='http://127.0.0.1:9/'`, test token only): `bash <pinned> recall ...` vs `python3 -m memory_router recall ...` on separate roots populated with MEMORY.md/USER.md (under & over budget), LEARNINGS/FACTS rows (current + stale), run-artifacts incl. a `STATE.md` and a `findings/*.md`, and a built RECALL.sqlite. Verify stdout byte-identical (compact + `--pretty`); on `--write` verify RECALL.md, RECALL.json, and MEMORY-USAGE.json byte-identical after normalizing `Generated:`/`updated_at`/`at`/`last_used_at` timestamps. Verify all 3 error paths (missing query, bad `--max`, missing query-file). Verify empty-query-terms fallback and the over-budget omitted list.
- ASCII check on every changed file -> clean.

## Self-Review (grounding evidence)

**Pre-implementation plan-audit** (external auditor vs pinned Bash): 0 BLOCKER/HIGH/MEDIUM; 5 LOW imprecisions, all folded into the code/plan (empty-`--max` rejected via `''|*[!0-9]*`; `estimated_tokens` reads the normalized `value.title/summary`; heading regex uses an explicit ASCII whitespace class, not `\s`; RECALL.md/.json atomic-write symlink default pinned; `cut -c` codepoint-slice noted). STATE.md divergence (Bash 1668 vs 2619) independently confirmed.

**Grounded byte-for-byte vs the real extracted Bash** (isolated `env -i PATH=... HOME=/tmp KIMIFLOW_OBSIDIAN_URL='http://127.0.0.1:9/'`, test token only):
- In-repo `RecallParityCase`: stdout identical for compact / `--pretty` / `--max 1` / no-match; over-budget (MEMORY/USER budget=1) identical; the written **RECALL.md**, **RECALL.json**, and **MEMORY-USAGE.json** identical after normalizing only `Generated:` / `updated_at` / `at` / `last_used_at`. Index-free (both report `index_status:missing`) so it never trips the documented bash-vs-stdlib index build row-count difference (S15203).
- Manual grounding (shared bash-built RECALL.sqlite so both readers use one DB): `index_status:used` (5 hits) and `available_no_hits` byte-identical; empty-query-terms fallback (`["the und"]`) identical; all 5 error paths (missing query, bad `--max`, empty trailing `--max`, missing query-file, unknown arg) identical message + exit 2.

**Independent senior-review** (vs Bash, all four files + reused helpers): 0 BLOCKER/HIGH, no fidelity bugs. Verified `terms_json_from_query`, `jsonl_hits` (`//` null/false vs 0/"", field_text, `.[:max]`), `update_usage_metrics` (hit_key branches, accumulating use_count without aliasing, value/event key order, `estimated_tokens`, `unique`->`sorted(set)`, `events[-100:]`, mv-vs-redirect -> `refuse_symlink=False`+0600), the `--write` usage set (learnings+index+history, not facts), reason_codes/included/omitted order, run-artifact source incl. STATE.md, and the markdown printf layout. Documented divergences (non-dict skip, non-object usage default, `fts5_available` substitution, `_int_env` raising on a non-numeric budget where Bash also fails) are the deliberate, safe ones now in spec §12.

**Suite:** 293 -> 342 tests, all green. ASCII-clean on every changed source file (middle-dot / e-acute written as `·` / `é` escapes).
