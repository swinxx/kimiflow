# memory-router Python CLI - Plan 7: `build_recall_index` (multi-source population)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `build_recall_index` (Bash 2547-2621) - the population layer that fills the Plan 6 FTS engine from every memory source: `MEMORY.md`/`USER.md` (first 180 lines), current `LEARNINGS.jsonl` / `USER.jsonl` rows, all `FACTS.jsonl` rows, and run-artifact `.md` files found under `.kimiflow` (excluding the pruned `project/` dir). Opens one connection, calls `init_recall_db`, then `insert_fts_row` per source. Returns `2` when FTS5 is unavailable (mirrors `sqlite_available || return 2`).

**Architecture:** Extend the existing `hooks/memory_router/recall_index.py` (Plan 6) with `build_recall_index` plus private helpers (`_read_body`, `_first_lines`, `_jq_or`, `_evidence_ref`, `_artifact_title`, `_iter_run_artifacts`) and a `_MIDDOT` / `_ARTIFACT_NAMES` constant. Consumes already-ported `clock.iso_now`, `paths.rel_path`, `store.read_jsonl`, and the Plan 6 engine (`fts5_available` / `init_recall_db` / `insert_fts_row`). Single Python `sqlite3` connection replaces the Bash one-`sqlite3`-subprocess-per-statement pattern; one `con.commit()` at the end. Lives in `recall_index.py` (not a new module) because it is the engine's dedicated populator.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `re`, `sqlite3`); no new third-party deps; no `sqlite3`/`jq`/`sed`/`awk`/`find` CLI dependency.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** no edits to `hooks/memory-router.sh`, SKILL.md, reference.md, manifests, or unrelated modules. This plan changes exactly: `recall_index.py` (extend), `tests/test_recall_index.py` (extend), and one row appended to spec §12. **No subcommand wiring** (Plan 8) - `build_recall_index` is an internal helper, unit-tested only; stdout/file parity arrives when `cmd_index`/`cmd_curate` wire it.
- **Source of truth:** Bash `build_recall_index` @ `kimiflow--v0.1.50` (2547-2621), plus `insert_fts_row` (2542-2545), `rel_path` (2514-2521), `sqlite_available` (2527-2529). Grounded against the real Bash function (extracted into a harness, run on a fixture, FTS contents diffed) - see Self-Review.
- **FTS5-unavailable guard:** `build_recall_index` returns `2` and does no db work when `fts5_available()` is false (Bash `sqlite_available || return 2`). The caller (`cmd_index`, Plan 8) already gates on availability first; this is the defensive inner guard.
- **Schema rebuild:** `init_recall_db` (Plan 6) drops+recreates `recall_meta`/`recall_fts` and stamps `updated_at`, so every call is a full rebuild (old rows gone). Bash 2559-2565.
- **Per-source contracts (Bash, exact):**
  - **MEMORY.md** → row `(kind="memory", source=".kimiflow/project/MEMORY.md", title="Project Memory", body=first-180-lines, ref=".kimiflow/project/MEMORY.md")`, only if the file exists.
  - **USER.md** → `(kind="user_profile", source=".kimiflow/project/USER.md", title="User Profile", body=first-180-lines, ref=".kimiflow/project/USER.md")`, only if it exists.
  - **LEARNINGS.jsonl** (current only) → `(kind="learning", source=".kimiflow/project/LEARNINGS.jsonl", title="<topic> · <kind> · <id>", body=<summary>, ref=evidence[0])`. Defaults: topic `uncategorized`, kind `learning`, summary `""`, evidence `[]`.
  - **USER.jsonl** (current only) → `(kind="user_profile", source=".kimiflow/project/USER.jsonl", title="<topic> · <id>", body=<summary>, ref=evidence[0])`. Default topic `profile`.
  - **FACTS.jsonl** (no status filter) → `(kind="fact", source=".kimiflow/project/FACTS.jsonl", title="<kind> · <area> · <path>", body=<summary>, ref="<path>:<line>")`. Defaults: kind `fact`, area `codebase`, path `""`, line `1`.
  - **run artifacts** → `(kind="run_artifact", source=<rel>, title="<2nd path component> · <path after first two components>", body=first-180-lines, ref=<rel>)`.
- **`//` semantics (jq → Python):** Bash uses jq `// default`, which substitutes the default when the value is JSON `null` **or** `false` (but **not** for `""`/`0`, which are truthy in jq). The port replicates this with `_jq_or`, not `dict.get(key, default)` - a row with `"status": null` is **kept** (jq `null // "current"` → `"current"`), where a naive `.get` would drop it. (Grounding caught this.)
- **`line` formatting:** Bash `((.line // 1) | tostring)`. jq 1.7 **preserves number literals**, so `7.0` renders as `"7.0"` (not `"7"`), `42` as `"42"`, `0` as `"0"`. Python `str(_jq_or(line, 1))` matches for integers and `X.0` floats (the realistic cases); exotic decimal formatting (e.g. `7.50`) is not literally preserved - `line` is expected to be an integer.
- **First-180-lines parity:** Bash `body="$(sed -n '1,180p' f)"`. `sed` splits on `\n` only; command substitution strips trailing newlines. Port: `_first_lines = "\n".join(text.split("\n")[:180]).rstrip("\n")` - matches line-count at the trailing-newline boundary, keeps interior blanks, strips trailing blank lines.
- **Newline-faithful read (`_read_body`):** body reads use `open(..., newline="")` (via `_read_body`), **not** `store.read_text`. `sed` keeps the `\r` on each CRLF line and treats a bare-`\r` file as one line; `store.read_text`'s universal-newline mode would translate `\r\n`/`\r` to `\n` *before* `_first_lines` runs, dropping the `\r` and mis-counting bare-CR lines. `newline=""` disables that translation so the stored body is byte-identical to `sed`. (`store.read_text` is left untouched — it has no other callers and keeps its general-purpose semantics.)
- **Run-artifact discovery:** Bash `find "$root/.kimiflow" -path "$project" -prune -o -type f \( -name '<NAME>' ... -o -path '*/findings/*.md' \) -print`. Matched basenames: `INTENT.md PROBLEM.md RESEARCH.md DIAGNOSIS.md PLAN.md ACCEPTANCE.md REVIEW.md CODE-REVIEW.md LEARNING-REVIEW.md ADVISORIES.md`; plus any `*.md` under a `findings/` directory. The `project/` subtree is pruned (its `MEMORY.md`/`USER.md`/`PLAN.md` are not re-indexed as artifacts). Port walks with `os.walk`, prunes `project`, matches by basename-or-`/findings/*.md`.
- **Run-artifact order (divergence, spec §12):** `find`'s native order is filesystem-dependent (undefined across hosts); the port **sorts** matched paths for deterministic insertion. Only observable via `fts_hits_json`'s `LIMIT` (no `ORDER BY`), where Bash is itself non-deterministic.
- **Middle dot:** the title joiner is U+00B7 MIDDLE DOT. Define it **once** as `_MIDDOT = "\u00b7"` (an ASCII escape) and never write the literal char anywhere in source. (Handoff gotcha: implementers tend to "helpfully" convert the escape back to a raw char.)
- **Nondeterminism:** `recall_meta.updated_at = clock.iso_now()` - tests monkeypatch it.
- **Commits:** named paths only; no co-author / AI-attribution trailer.
- **Branch:** continue on `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/recall_index.py` | **extend** with `_ARTIFACT_NAMES`, `_MIDDOT`, `_read_body`, `_first_lines`, `_jq_or`, `_evidence_ref`, `_artifact_title`, `_iter_run_artifacts`, `build_recall_index`; widen the import to `from . import clock, paths, store`. |
| `hooks/memory_router/tests/test_recall_index.py` | **extend** with `HelperCase` (helper unit tests) + `BuildRecallIndexCase` (per-source population, status filter incl. `null`, defaults, facts line formatting, 180-line bodies, CRLF body, run-artifact match/prune/sort, empty project, rebuild, FTS5-unavailable). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (run-artifact order + malformed-JSONL-line handling). |

---

### Task 1: `build_recall_index` population (`recall_index.py`)

**Files:**
- Edit: `hooks/memory_router/recall_index.py`
- Test: `hooks/memory_router/tests/test_recall_index.py`
- Edit: spec §12 (append one divergence row)

**Interfaces:**
- Consumes: `clock.iso_now`, `paths.rel_path`, `store.read_text`, `store.read_jsonl`, and Plan 6 `fts5_available` / `init_recall_db` / `insert_fts_row`.
- Produces (Plan 8 `cmd_index` / `cmd_curate` consume): `recall_index.build_recall_index(root, db_path) -> int` (0 success, 2 FTS5-unavailable).

- [ ] **Step 1: Write the failing tests** - replace `tests/test_recall_index.py` with the full file below (it keeps the Plan 6 cases and adds `HelperCase` + `BuildRecallIndexCase`).

```python
# hooks/memory_router/tests/test_recall_index.py
import json
import os
import shutil
import sqlite3
import tempfile
import unittest
from unittest import mock

from memory_router import recall_index

ISO = "2026-06-29T00:00:00Z"
DOT = "\u00b7"  # U+00B7 MIDDLE DOT (never write the literal char in source).


class FtsQueryFromTermsCase(unittest.TestCase):
    def q(self, terms):
        return recall_index.fts_query_from_terms(terms)

    def test_basic_sorted_and_quoted(self):
        self.assertEqual(self.q(["build", "auth"]), '"auth" OR "build"')

    def test_strips_non_term_chars(self):
        self.assertEqual(self.q(["foo-bar!"]), '"foobar"')

    def test_drops_terms_shorter_than_three(self):
        self.assertEqual(self.q(["ab", "abc", "x"]), '"abc"')

    def test_unique_dedups_and_sorts(self):
        self.assertEqual(self.q(["zoo", "abc", "abc", "zoo"]), '"abc" OR "zoo"')

    def test_underscore_kept(self):
        self.assertEqual(self.q(["foo_bar"]), '"foo_bar"')

    def test_empty_when_all_filtered(self):
        self.assertEqual(self.q(["a", "b!", ""]), "")

    def test_length_measured_after_stripping(self):
        # "a-b" strips to "ab" (len 2) -> dropped.
        self.assertEqual(self.q(["a-b"]), "")


class FtsEngineCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.project = os.path.join(self.root, ".kimiflow", "project")
        os.makedirs(self.project, exist_ok=True)
        self.db = recall_index.recall_db_path(self.root)
        p = mock.patch("memory_router.clock.iso_now", return_value=ISO)
        p.start()
        self.addCleanup(p.stop)

    def build(self, rows):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        for r in rows:
            recall_index.insert_fts_row(con, *r)
        con.commit()
        con.close()

    def test_fts5_available(self):
        self.assertTrue(recall_index.fts5_available())

    def test_init_stamps_updated_at(self):
        con = sqlite3.connect(self.db)
        recall_index.init_recall_db(con)
        con.commit()
        value = con.execute(
            "SELECT value FROM recall_meta WHERE key = 'updated_at'"
        ).fetchone()[0]
        con.close()
        self.assertEqual(value, ISO)

    def test_query_roundtrip_returns_hit_shape(self):
        self.build([
            ("learning", ".kimiflow/project/LEARNINGS.jsonl", "build flow",
             "we fixed the build flow and release convention", "src/foo.py:5"),
            ("memory", ".kimiflow/project/MEMORY.md", "Project Memory",
             "auth token rotation chosen", ".kimiflow/project/MEMORY.md"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits), 1)
        self.assertEqual(hits[0], {
            "kind": "learning",
            "source": ".kimiflow/project/LEARNINGS.jsonl",
            "title": "build flow",
            "ref": "src/foo.py:5",
            "summary": "we fixed the build flow and release convention",
        })

    def test_or_query_matches_multiple(self):
        self.build([
            ("learning", "L", "t1", "build pipeline", "r1"),
            ("memory", "M", "t2", "auth rotation", "r2"),
            ("fact", "F", "t3", "unrelated text", "r3"),
        ])
        hits = recall_index.fts_hits_json(self.root, ["build", "auth"], 10)
        self.assertEqual({h["ref"] for h in hits}, {"r1", "r2"})

    def test_limit_respected(self):
        self.build([("learning", "L", "t%d" % i, "build flow", "r%d" % i) for i in range(5)])
        self.assertEqual(len(recall_index.fts_hits_json(self.root, ["build"], 2)), 2)

    def test_summary_truncated_to_420(self):
        self.build([("learning", "L", "t", "build " + "x" * 500, "r")])
        hits = recall_index.fts_hits_json(self.root, ["build"], 10)
        self.assertEqual(len(hits[0]["summary"]), 420)

    def test_missing_db_returns_empty(self):
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_empty_query_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        self.assertEqual(recall_index.fts_hits_json(self.root, ["ab", "x"], 10), [])

    def test_corrupt_db_returns_empty(self):
        with open(self.db, "w", encoding="utf-8") as fh:
            fh.write("this is not a sqlite database")
        self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])

    def test_unavailable_fts5_returns_empty(self):
        self.build([("learning", "L", "t", "build flow", "r")])
        with mock.patch("memory_router.recall_index.fts5_available", return_value=False):
            self.assertEqual(recall_index.fts_hits_json(self.root, ["build"], 10), [])


class HelperCase(unittest.TestCase):
    def test_jq_or_substitutes_null_and_false(self):
        self.assertEqual(recall_index._jq_or(None, "d"), "d")
        self.assertEqual(recall_index._jq_or(False, "d"), "d")

    def test_jq_or_passes_through_falsy_truthy_values(self):
        # In jq, empty string and 0 are truthy -> pass through unchanged.
        self.assertEqual(recall_index._jq_or("", "d"), "")
        self.assertEqual(recall_index._jq_or(0, "d"), 0)
        self.assertEqual(recall_index._jq_or("x", "d"), "x")

    def test_first_lines_caps_and_strips_trailing_newlines(self):
        text = "\n".join("l%d" % i for i in range(1, 201)) + "\n\n\n"
        out = recall_index._first_lines(text)
        self.assertEqual(out.split("\n"), ["l%d" % i for i in range(1, 181)])

    def test_first_lines_keeps_interior_blank_lines(self):
        self.assertEqual(recall_index._first_lines("a\n\nb\n"), "a\n\nb")

    def test_first_lines_splits_only_on_newline(self):
        # sed splits on \n only; a CRLF leaves the \r on the line.
        self.assertEqual(recall_index._first_lines("a\r\nb\r\n"), "a\r\nb\r")

    def test_first_lines_all_blank_collapses_to_empty(self):
        self.assertEqual(recall_index._first_lines("\n\n"), "")

    def test_artifact_title_drops_first_two_components(self):
        self.assertEqual(
            recall_index._artifact_title(".kimiflow/runs/2026/INTENT.md"),
            "runs " + DOT + " 2026/INTENT.md",
        )

    def test_artifact_title_two_component_path(self):
        self.assertEqual(
            recall_index._artifact_title(".kimiflow/PLAN.md"),
            "PLAN.md " + DOT + " ",
        )

    def test_evidence_ref_picks_first_or_empty(self):
        self.assertEqual(recall_index._evidence_ref({"evidence": ["a", "b"]}), "a")
        self.assertEqual(recall_index._evidence_ref({"evidence": []}), "")
        self.assertEqual(recall_index._evidence_ref({"evidence": None}), "")
        self.assertEqual(recall_index._evidence_ref({}), "")
        self.assertEqual(recall_index._evidence_ref({"evidence": "notalist"}), "")


class BuildRecallIndexCase(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.project = os.path.join(self.root, ".kimiflow", "project")
        os.makedirs(self.project, exist_ok=True)
        self.db = recall_index.recall_db_path(self.root)
        p = mock.patch("memory_router.clock.iso_now", return_value=ISO)
        p.start()
        self.addCleanup(p.stop)

    def write(self, relpath, text):
        full = os.path.join(self.root, relpath)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(text)

    def write_jsonl(self, relpath, rows):
        self.write(relpath, "".join(json.dumps(r) + "\n" for r in rows))

    def rows(self):
        rc = recall_index.build_recall_index(self.root, self.db)
        self.assertEqual(rc, 0)
        con = sqlite3.connect(self.db)
        out = con.execute(
            "SELECT kind, source, title, body, ref FROM recall_fts ORDER BY rowid"
        ).fetchall()
        con.close()
        return out

    def by_kind(self, kind):
        return [r for r in self.rows() if r[0] == kind]

    def test_returns_2_when_fts5_unavailable(self):
        with mock.patch("memory_router.recall_index.fts5_available", return_value=False):
            self.assertEqual(recall_index.build_recall_index(self.root, self.db), 2)
        self.assertFalse(os.path.exists(self.db))

    def test_empty_project_only_meta_row(self):
        rc = recall_index.build_recall_index(self.root, self.db)
        self.assertEqual(rc, 0)
        con = sqlite3.connect(self.db)
        self.assertEqual(con.execute("SELECT count(*) FROM recall_fts").fetchone()[0], 0)
        meta = con.execute("SELECT key, value FROM recall_meta").fetchall()
        con.close()
        self.assertEqual(meta, [("updated_at", ISO)])

    def test_rebuild_drops_previous_rows(self):
        self.write(".kimiflow/project/MEMORY.md", "one\n")
        self.assertEqual(len(self.by_kind("memory")), 1)
        # Rebuild after removing the source -> the old row must be gone.
        os.remove(os.path.join(self.project, "MEMORY.md"))
        self.assertEqual(len(self.by_kind("memory")), 0)

    def test_memory_and_user_md_first_180_lines(self):
        self.write(".kimiflow/project/MEMORY.md",
                   "\n".join("m%d" % i for i in range(1, 201)) + "\n\n")
        self.write(".kimiflow/project/USER.md", "prefers 'concise'\nno emoji\n")
        rows = self.rows()
        mem = [r for r in rows if r[0] == "memory"][0]
        self.assertEqual(mem[1], ".kimiflow/project/MEMORY.md")
        self.assertEqual(mem[2], "Project Memory")
        self.assertEqual(mem[4], ".kimiflow/project/MEMORY.md")
        self.assertEqual(mem[3].split("\n"), ["m%d" % i for i in range(1, 181)])
        user = [r for r in rows if r[0] == "user_profile" and r[1].endswith("USER.md")][0]
        self.assertEqual(user[2], "User Profile")
        self.assertEqual(user[3], "prefers 'concise'\nno emoji")

    def test_learnings_status_filter_and_defaults(self):
        self.write_jsonl(".kimiflow/project/LEARNINGS.jsonl", [
            {"id": "l1", "status": "current", "kind": "gotcha", "topic": "sqlite",
             "summary": "fts5 here", "evidence": ["x.sh:10", "y"]},
            {"id": "l2", "status": "superseded", "topic": "old", "summary": "drop"},
            {"id": "l3"},  # all defaults
            {"id": "l4", "status": None, "kind": "pattern", "topic": "nul"},  # null kept
        ])
        rows = self.by_kind("learning")
        titles = [r[2] for r in rows]
        self.assertEqual(titles, [
            "sqlite " + DOT + " gotcha " + DOT + " l1",
            "uncategorized " + DOT + " learning " + DOT + " l3",
            "nul " + DOT + " pattern " + DOT + " l4",
        ])
        self.assertEqual(rows[0][3], "fts5 here")          # body = summary
        self.assertEqual(rows[0][4], "x.sh:10")            # ref = evidence[0]
        self.assertEqual(rows[1][3], "")                   # default summary
        self.assertEqual(rows[1][4], "")                   # default evidence ref

    def test_user_rows_status_filter_and_defaults(self):
        self.write_jsonl(".kimiflow/project/USER.jsonl", [
            {"id": "u1", "status": "current", "topic": "tone", "summary": "direct",
             "evidence": ["chat:1"]},
            {"id": "u2", "status": "archived", "topic": "x"},
            {"id": "u3"},  # defaults: topic=profile
        ])
        rows = [r for r in self.by_kind("user_profile") if r[1].endswith("USER.jsonl")]
        self.assertEqual([r[2] for r in rows], ["tone " + DOT + " u1", "profile " + DOT + " u3"])
        self.assertEqual(rows[0][4], "chat:1")

    def test_facts_title_ref_and_line_formatting(self):
        self.write_jsonl(".kimiflow/project/FACTS.jsonl", [
            {"kind": "module", "area": "hooks", "path": "a.py", "line": 42, "summary": "fa"},
            {"area": "core", "path": "b.py", "summary": "no line"},   # kind=fact, line=1
            {"kind": "fn", "path": "c.py", "line": 7.0},              # area=codebase, 7.0 kept
            {"kind": "z", "area": "d", "path": "d.py", "line": 0},    # 0 stays 0
        ])
        rows = self.by_kind("fact")
        self.assertEqual([r[2] for r in rows], [
            "module " + DOT + " hooks " + DOT + " a.py",
            "fact " + DOT + " core " + DOT + " b.py",
            "fn " + DOT + " codebase " + DOT + " c.py",
            "z " + DOT + " d " + DOT + " d.py",
        ])
        self.assertEqual([r[4] for r in rows], ["a.py:42", "b.py:1", "c.py:7.0", "d.py:0"])

    def test_run_artifacts_match_prune_and_sort(self):
        self.write(".kimiflow/runs/demo/INTENT.md", "intent\n")
        self.write(".kimiflow/runs/demo/PLAN.md", "plan\n")
        self.write(".kimiflow/runs/demo/findings/f1.md", "finding\n")
        self.write(".kimiflow/runs/demo/NOTES.md", "excluded\n")        # not a matched name
        self.write(".kimiflow/project/PLAN.md", "pruned project file\n")  # pruned subtree
        rows = self.by_kind("run_artifact")
        self.assertEqual([r[1] for r in rows], [
            ".kimiflow/runs/demo/INTENT.md",
            ".kimiflow/runs/demo/PLAN.md",
            ".kimiflow/runs/demo/findings/f1.md",
        ])
        self.assertEqual(rows[0][2], "runs " + DOT + " demo/INTENT.md")
        self.assertEqual(rows[2][2], "runs " + DOT + " demo/findings/f1.md")
        self.assertEqual(rows[0][3], "intent")  # body = first lines

    def test_run_artifact_body_first_180_lines(self):
        self.write(".kimiflow/runs/demo/PLAN.md",
                   "\n".join("p%d" % i for i in range(1, 201)) + "\n")
        body = self.by_kind("run_artifact")[0][3]
        self.assertEqual(body.split("\n"), ["p%d" % i for i in range(1, 181)])

    def test_body_read_preserves_crlf_like_sed(self):
        # Bash `sed -n '1,180p'` splits on \n only and keeps the \r per line; the
        # read must not translate newlines (universal-newline mode would drop \r).
        full = os.path.join(self.project, "MEMORY.md")
        with open(full, "w", encoding="utf-8", newline="") as fh:
            fh.write("a\r\nb\r\n")
        self.assertEqual(self.by_kind("memory")[0][3], "a\r\nb\r")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_recall_index -v`
Expected: FAIL - `AttributeError: module 'memory_router.recall_index' has no attribute 'build_recall_index'` (and `_jq_or` etc.). The Plan 6 cases still pass.

- [ ] **Step 3: Extend `recall_index.py`** - the full file below is the Plan 6 engine plus the Plan 7 additions. `_MIDDOT` is the **only** non-ASCII-valued constant and it is written as a `·` escape; the source file must stay pure ASCII.

```python
# hooks/memory_router/recall_index.py
"""RECALL.sqlite FTS5 engine: availability probe, schema init, row insert, term ->
MATCH-query construction, and the hit query with graceful degradation. Behavioral
port of the Bash sqlite_available / fts_query_from_terms / insert_fts_row / the
recall schema / fts_hits_json at kimiflow--v0.1.50 (2527-2644). Uses the Python
stdlib `sqlite3` module instead of shelling to the `sqlite3` CLI."""
import os
import re
import sqlite3

from . import clock, paths, store

# Source of truth: Bash 2562-2563.
_SCHEMA = (
    "DROP TABLE IF EXISTS recall_meta;\n"
    "DROP TABLE IF EXISTS recall_fts;\n"
    "CREATE TABLE recall_meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);\n"
    "CREATE VIRTUAL TABLE recall_fts USING fts5(kind, source, title, body, ref);"
)

_NON_TERM = re.compile(r"[^A-Za-z0-9_]")

# Bash build_recall_index run-artifact filter (2613-2620): match these basenames
# anywhere under .kimiflow (except the pruned project dir), plus any *.md under a
# findings/ directory.
_ARTIFACT_NAMES = frozenset((
    "INTENT.md", "PROBLEM.md", "RESEARCH.md", "DIAGNOSIS.md", "PLAN.md",
    "ACCEPTANCE.md", "REVIEW.md", "CODE-REVIEW.md", "LEARNING-REVIEW.md",
    "ADVISORIES.md",
))
_MIDDOT = "\u00b7"  # U+00B7 MIDDLE DOT; never write the literal char (handoff gotcha).


def fts5_available():
    # Bash gates on `command -v sqlite3` (the CLI). The stdlib sqlite3 module is
    # always importable, but FTS5 may not be compiled in, so we probe it. See spec 12.
    try:
        con = sqlite3.connect(":memory:")
    except sqlite3.Error:
        return False
    try:
        con.execute("CREATE VIRTUAL TABLE _probe USING fts5(x)")
        return True
    except sqlite3.Error:
        return False
    finally:
        con.close()


def recall_db_path(root):
    return os.path.join(root, ".kimiflow", "project", "RECALL.sqlite")


def init_recall_db(con):
    # Bash 2559-2565: drop+create the schema, then stamp recall_meta.updated_at.
    # Caller must confirm fts5_available() first (the CREATE VIRTUAL TABLE here
    # would raise sqlite3.OperationalError otherwise).
    con.executescript(_SCHEMA)
    con.execute(
        "INSERT INTO recall_meta(key, value) VALUES('updated_at', ?)", (clock.iso_now(),)
    )


def insert_fts_row(con, kind, source, title, body, ref):
    # Bash 2542-2545 uses sql_quote string interpolation; the stdlib module binds
    # parameters instead (equivalent result, no quoting bugs).
    con.execute(
        "INSERT INTO recall_fts(kind, source, title, body, ref) VALUES(?, ?, ?, ?, ?)",
        (kind, source, title, body, ref),
    )


def fts_query_from_terms(terms):
    # Bash 2531-2540 (jq): strip each term to [A-Za-z0-9_], keep length >= 3,
    # `unique` (jq sorts + dedups), quote each, join with " OR ".
    cleaned = {_NON_TERM.sub("", str(term)) for term in terms}
    kept = sorted(t for t in cleaned if len(t) >= 3)
    return " OR ".join('"' + t + '"' for t in kept)


def fts_hits_json(root, terms, max_hits):
    # Bash 2623-2644: graceful degradation -> [] when sqlite/fts5 absent, db missing,
    # query empty, or any sqlite error.
    db = recall_db_path(root)
    if not fts5_available() or not os.path.isfile(db):
        return []
    query = fts_query_from_terms(terms)
    if not query:
        return []
    try:
        con = sqlite3.connect(db)
    except sqlite3.Error:
        return []
    try:
        cur = con.execute(
            "SELECT kind, source, title, ref, substr(body, 1, 420) AS summary "
            "FROM recall_fts WHERE recall_fts MATCH ? LIMIT ?",
            (query, max_hits),
        )
        columns = [d[0] for d in cur.description]
        return [dict(zip(columns, row)) for row in cur.fetchall()]
    except sqlite3.Error:
        return []
    finally:
        con.close()


def _read_body(path):
    # Bash reads the file via `sed`, which splits on \n only and leaves any \r in
    # place. newline="" disables Python's universal-newline translation so \r\n /
    # bare \r survive to _first_lines (store.read_text would collapse them to \n).
    try:
        with open(path, "r", encoding="utf-8", newline="") as handle:
            return handle.read()
    except (OSError, UnicodeDecodeError):
        return ""


def _first_lines(text, count=180):
    # Bash `body="$(sed -n '1,180p' file)"`: take the first `count` lines (sed splits
    # only on \n), then command substitution strips trailing newlines.
    return "\n".join(text.split("\n")[:count]).rstrip("\n")


def _jq_or(value, default):
    # jq `value // default`: substitute the default when value is null (None) or
    # false. An empty string / 0 is truthy in jq and passes through unchanged.
    return default if value is None or value is False else value


def _evidence_ref(row):
    # jq `(.evidence // []) | .[0] // ""`: first evidence entry, or "" when the list
    # is missing/empty/non-indexable or its first entry is null/false.
    evidence = _jq_or(row.get("evidence"), [])
    first = evidence[0] if isinstance(evidence, list) and evidence else None
    first = _jq_or(first, "")
    return "" if first == "" else str(first)


def _artifact_title(rel):
    # Bash awk -F/ '{print $2 " <middot> " substr($0, length($1 "/" $2 "/") + 1)}':
    # second path component, then everything after the first two components.
    parts = rel.split("/")
    second = parts[1] if len(parts) > 1 else ""
    prefix_len = len(parts[0]) + 1 + len(second) + 1  # length("$1/$2/")
    return second + " " + _MIDDOT + " " + rel[prefix_len:]


def _iter_run_artifacts(root):
    # Bash find: traverse $root/.kimiflow, prune the project dir, then yield regular
    # files whose basename is a matched name OR whose path is */findings/*.md.
    base = os.path.join(root, ".kimiflow")
    project = os.path.join(base, "project")
    matches = []
    for dirpath, dirnames, filenames in os.walk(base):
        if dirpath == project:
            dirnames[:] = []  # prune: do not descend into .kimiflow/project
            continue
        for name in filenames:
            full = os.path.join(dirpath, name)
            rel = paths.rel_path(root, full)
            if name in _ARTIFACT_NAMES or ("/findings/" in rel and rel.endswith(".md")):
                matches.append((rel, full))
    # find's native order is filesystem-dependent; sort for deterministic insertion
    # (observable only via fts_hits_json LIMIT, which has no ORDER BY).
    matches.sort()
    return matches


def build_recall_index(root, db_path):
    """Populate RECALL.sqlite from all memory sources. Port of Bash build_recall_index
    (2547-2621). Returns 2 when FTS5 is unavailable (mirrors `sqlite_available ||
    return 2`), else 0 after committing the rebuilt index."""
    if not fts5_available():
        return 2
    project = os.path.join(root, ".kimiflow", "project")
    memory = os.path.join(project, "MEMORY.md")
    user_memory = os.path.join(project, "USER.md")
    learnings = os.path.join(project, "LEARNINGS.jsonl")
    user_rows = os.path.join(project, "USER.jsonl")
    facts = os.path.join(project, "FACTS.jsonl")
    os.makedirs(project, exist_ok=True)

    con = sqlite3.connect(db_path)
    try:
        init_recall_db(con)

        if os.path.isfile(memory):
            body = _first_lines(_read_body(memory))
            insert_fts_row(con, "memory", ".kimiflow/project/MEMORY.md",
                           "Project Memory", body, ".kimiflow/project/MEMORY.md")
        if os.path.isfile(user_memory):
            body = _first_lines(_read_body(user_memory))
            insert_fts_row(con, "user_profile", ".kimiflow/project/USER.md",
                           "User Profile", body, ".kimiflow/project/USER.md")

        for row in store.read_jsonl(learnings):
            if _jq_or(row.get("status"), "current") != "current":
                continue
            title = "%s %s %s %s %s" % (
                _jq_or(row.get("topic"), "uncategorized"), _MIDDOT,
                _jq_or(row.get("kind"), "learning"), _MIDDOT, _jq_or(row.get("id"), ""))
            insert_fts_row(con, "learning", ".kimiflow/project/LEARNINGS.jsonl",
                           title, str(_jq_or(row.get("summary"), "")), _evidence_ref(row))

        for row in store.read_jsonl(user_rows):
            if _jq_or(row.get("status"), "current") != "current":
                continue
            title = "%s %s %s" % (
                _jq_or(row.get("topic"), "profile"), _MIDDOT, _jq_or(row.get("id"), ""))
            insert_fts_row(con, "user_profile", ".kimiflow/project/USER.jsonl",
                           title, str(_jq_or(row.get("summary"), "")), _evidence_ref(row))

        for row in store.read_jsonl(facts):
            inner = "%s %s %s" % (
                _jq_or(row.get("area"), "codebase"), _MIDDOT, _jq_or(row.get("path"), ""))
            title = "%s %s %s" % (_jq_or(row.get("kind"), "fact"), _MIDDOT, inner)
            ref = "%s:%s" % (_jq_or(row.get("path"), ""), str(_jq_or(row.get("line"), 1)))
            insert_fts_row(con, "fact", ".kimiflow/project/FACTS.jsonl",
                           title, str(_jq_or(row.get("summary"), "")), ref)

        for rel, full in _iter_run_artifacts(root):
            body = _first_lines(_read_body(full))
            insert_fts_row(con, "run_artifact", rel, _artifact_title(rel), body, rel)

        con.commit()
    finally:
        con.close()
    return 0
```

- [ ] **Step 4: Run the focused tests to verify they pass**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_recall_index -v`
Expected: PASS - 36 tests OK (the prior 17 Plan-6 cases plus the new `HelperCase` + `BuildRecallIndexCase`).

- [ ] **Step 5: Byte-check the changed source is pure ASCII**

Run: `python3 -c "import sys; [print('NON-ASCII', i+1, repr(l)) for i,l in enumerate(open('hooks/memory_router/recall_index.py',encoding='utf-8')) if any(ord(c)>127 for c in l)] or print('recall_index.py: pure ASCII')"`
And the same for `hooks/memory_router/tests/test_recall_index.py`.
Expected: both report **pure ASCII** (the `·` escape is six ASCII chars; no raw U+00B7 may appear).

- [ ] **Step 6: Run the full package suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (139 tests: 120 prior + 19 new recall_index cases). `PATH` exports homebrew so the `contracts` test finds `jq`.

- [ ] **Step 7: Append spec §12 divergence row**

Append to the table in `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` §12:

```
| `build_recall_index` run-artifact order + malformed rows | `find` emits run-artifact files in filesystem (readdir) order; jq parses each JSONL line and an unparseable line yields empty fields (FACTS would still insert an all-empty row) | run-artifact paths are **sorted** before insertion; `store.read_jsonl` **skips** unparseable lines entirely | `find`'s order is undefined across hosts, so a stable sort is chosen for reproducible indexes (observable only via `fts_hits_json` LIMIT, which has no ORDER BY - Bash is non-deterministic there too). Skipping malformed JSONL is the project-wide `read_jsonl` convention (Plans 4/5); it only diverges for FACTS, where Bash has no status filter to drop the garbage row. jq `//` null/false handling, jq-1.7 number-literal preservation (`7.0` → `"7.0"`), and `sed`'s newline handling (CRLF/bare-CR kept verbatim via a `newline=""` read) are **replicated** (`_jq_or` + `str` + `_read_body`), so they are not divergences. |
```

- [ ] **Step 8: Commit**

```bash
git add hooks/memory_router/recall_index.py hooks/memory_router/tests/test_recall_index.py docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "feat(memory_router): build_recall_index multi-source population"
```

---

## Self-Review

**1. Spec coverage:** `build_recall_index` maps verbatim - the 6 source loops (MEMORY.md, USER.md, LEARNINGS.jsonl current, USER.jsonl current, FACTS.jsonl, run artifacts), the FTS5-unavailable `return 2` guard, the full-rebuild schema, and the `· `-joined titles. No subcommand touched; the Plan 6 engine is unchanged (only the import line widens).

**2. Empirical grounding (the decisive check):** the real Bash `build_recall_index` (+ `insert_fts_row`/`rel_path`/`sql_quote`/`sqlite_available`) was extracted into a harness and run on a fixture exercising every source (200-line MEMORY.md with trailing blanks, current/superseded/defaults/`status:null` learning rows, current/archived/defaults user rows, FACTS with int/missing/`7.0`/`0` lines, run artifacts incl. a `findings/*.md`, a non-matching `NOTES.md`, and a pruned `project/PLAN.md`). The Python port produced a **byte-for-byte identical FTS row set** (14 rows: same `kind/source/title/ref` and same body SHA), identical schema, and identical empty-project output (only the `updated_at` meta row). Two divergences surfaced from this fixture and were fixed before the first commit: (a) `status:null` must be kept (jq `//`), (b) `line: 7.0` must render `"7.0"` (jq-1.7 literal preservation). An independent review then found a third: (c) CRLF/bare-`\r` bodies were collapsed to `\n` by `store.read_text`'s universal-newline mode - fixed by reading via `_read_body` (`newline=""`), re-grounded against `sed` (byte-identical). The only remaining difference is run-artifact insertion order (sorted vs `find` order - documented §12).

**3. Placeholder scan:** complete code in every step; no TBD/vague items; `_MIDDOT` is the sole non-ASCII *value*, written as a `·` escape - Step 5 enforces pure-ASCII source.

**4. Type consistency:** `build_recall_index(root, db_path) -> int` (0 / 2); helpers are pure string/list functions; reuses Plan 6 connection-taking `init_recall_db`/`insert_fts_row`. Single connection + one `commit()` replaces Bash's per-statement subprocesses.

## Notes for later plans (not part of this plan)
- **Plan 8 wiring - `cmd_index` / `cmd_curate`:** gate on `fts5_available()` (emit the `status:"unavailable"` JSON when false), then `build_recall_index(root, recall_db_path(root))`, then `SELECT count(*) FROM recall_fts` for the `documents` field. `cmd_curate` also builds the inline `MEMORY-INDEX.json` (Bash 4109, inside `cmd_curate`, not a standalone fn). First stdout/file parity for the write+index path; harness normalizes `updated_at` and whitelists run-artifact order.
- **`recall` subcommand** consumes `fts_hits_json` (Plan 6).
