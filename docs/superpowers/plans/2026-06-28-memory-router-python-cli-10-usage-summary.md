# memory-router Python CLI - Plan 10: `usage_summary_json`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port `usage_summary_json` (Bash 184-241) - the `MEMORY-USAGE.json` aggregator. It reads a single JSON object (`.items` map + `.events` array) and returns a fixed-shape usage/economics summary: tracked-item and event counts, `by_kind`/`by_event` reductions (the latter with per-kind `{writes,hits,estimated_tokens,last_at}` accumulation), an `economics` block, and `hot_items`. Consumed later by `status_json`.

**Architecture:** Extend `hooks/memory_router/summaries.py` (Plan 9) with `usage_summary_json` plus two private helpers: `_max_present` (the jq `sort | last` of non-null/false values, shared by `last_used_at`/`by_event.last_at`/`last_event_at`) and `_usage_absent` (the absent-shape literal). Reuses `store.read_json` + the existing `_jq_or`. Returns a Python **dict** (serialized at the `contracts.dumps` boundary later). No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only; no new deps.

## Global Constraints

- **Python floor:** 3.9+, stdlib-only.
- **Drop-in / scope:** changes exactly: `summaries.py` (extend), `tests/test_summaries.py` (extend), one §12 row. No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash `usage_summary_json` (184-241) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (key order + values) against the real extracted Bash function across 8 fixtures - see Self-Review.
- **Absent shape** (Bash guard `[ ! -f ] || ! jq -e .`): returned when the file is missing, invalid JSON, or top-level `null`/`false`. Port: `store.read_json` -> `None` for missing/invalid/`null`; `_usage_absent()` when the parsed value is not a dict (covers `None`, `False`, and - see divergence - any non-object). Exact absent key order: `present, path, tracked_items, total_uses, last_used_at, by_kind, events_tracked, by_event, economics, hot_items` with `economics: {recall_writes, history_writes, total_hit_count, estimated_output_tokens, last_event_at}`.
- **Present shape** (same key order, `present:true`):
  - `tracked_items` = `len(.items)`. `.items // {}` and `.events // []` default null/missing to empty (and a non-dict/non-list is coerced to empty).
  - `total_uses` = sum of `_jq_or(.use_count, 0)` over item values (jq `add // 0`; empty -> 0).
  - `last_used_at` = max of item `last_used_at` values, skipping null/false/missing (jq `// empty | sort | last // null`).
  - `by_kind` = count per `_jq_or(.kind, "unknown")` over item values, in **first-appearance order** (jq `reduce`).
  - `events_tracked` = `len(.events)`.
  - `by_event` = per-kind accumulator `{writes, hits, estimated_tokens, last_at}` (sub-object key order fixed), reduced over events in array order, keyed in first-appearance order: `writes += 1`, `hits += _jq_or(.hit_count,0)`, `estimated_tokens += _jq_or(.estimated_tokens,0)`, `last_at = _max_present([last_at, _jq_or(.at, None)])`.
  - `economics`: `recall_writes`/`history_writes` = count events whose `_jq_or(.kind,"") ==` `"recall"`/`"history"`; `total_hit_count`/`estimated_output_tokens` = summed; `last_event_at` = max event `.at` skipping null/false/missing.
  - `hot_items` = count item values with `_jq_or(.use_count, 0) > 1`.
- **`_max_present(values)`** captures all three jq max idioms: `[... // empty] | sort | last // null` (last_used_at, last_event_at) and `[a, (.x // null)] | map(select(. != null)) | sort | last // null` (by_event.last_at). Both keep only non-null, non-false values, sort, take the max; `None` when empty.
- **`by_kind`/`by_event` use first-appearance order** (jq `reduce`), unlike `read_jsonl_summary.by_topic` (sorted). Item iteration follows `MEMORY-USAGE.json` object key order (preserved by `json.load`).
- **Divergence (spec §12, unreachable):** for a **valid non-object** top level (e.g. `[1,2]`), Bash `jq -e .` passes then `.items` errors (empty stdout, breaks the caller); the port returns the absent shape (strictly more robust). Unreachable for real `MEMORY-USAGE.json` (always an object).
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/summaries.py` | add `_USAGE_PATH`, `_max_present`, `_usage_absent`, `usage_summary_json`. |
| `hooks/memory_router/tests/test_summaries.py` | add `UsageSummaryCase` (+ `write_raw` helper on `_FixtureCase`). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append one §12 row (non-object usage JSON). |

---

### Task 1: `usage_summary_json`

**Files:** Edit `summaries.py`, `tests/test_summaries.py`; Edit spec §12.

**Interfaces:** Produces `summaries.usage_summary_json(path) -> dict`. Consumes `store.read_json`, `_jq_or`.

- [ ] **Step 1: Add the tests** - on `_FixtureCase` add a `write_raw` helper, and append `UsageSummaryCase`:

```python
    # add to _FixtureCase
    def write_raw(self, name, text):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        return path
```

```python
class UsageSummaryCase(_FixtureCase):
    PATH = ".kimiflow/project/MEMORY-USAGE.json"
    ABSENT = {
        "present": False, "path": PATH, "tracked_items": 0, "total_uses": 0,
        "last_used_at": None, "by_kind": {}, "events_tracked": 0, "by_event": {},
        "economics": {
            "recall_writes": 0, "history_writes": 0, "total_hit_count": 0,
            "estimated_output_tokens": 0, "last_event_at": None,
        },
        "hot_items": 0,
    }

    def test_missing_file_absent_shape(self):
        r = summaries.usage_summary_json(self.missing("none.json"))
        self.assertEqual(r, self.ABSENT)
        self.assertEqual(list(r.keys()), list(self.ABSENT.keys()))
        self.assertEqual(list(r["economics"].keys()), list(self.ABSENT["economics"].keys()))

    def test_invalid_json_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("b.json", "not json{")), self.ABSENT)

    def test_literal_null_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("n.json", "null")), self.ABSENT)

    def test_literal_false_absent(self):
        self.assertEqual(summaries.usage_summary_json(self.write_raw("f.json", "false")), self.ABSENT)

    def test_non_object_json_absent_divergence(self):
        # Bash jq-errors on `.items` for a non-object top level (empty output, breaks the
        # caller); the port returns the absent shape instead. Unreachable for real files.
        self.assertEqual(summaries.usage_summary_json(self.write_raw("a.json", "[1,2,3]")), self.ABSENT)

    def test_empty_object_present_all_zero(self):
        r = summaries.usage_summary_json(self.write_raw("e.json", "{}"))
        self.assertTrue(r["present"])
        self.assertEqual(r["tracked_items"], 0)
        self.assertEqual(r["by_kind"], {})
        self.assertEqual(r["economics"]["total_hit_count"], 0)

    def test_items_and_events_null_default_to_empty(self):
        r = summaries.usage_summary_json(self.write_raw("z.json", '{"items":null,"events":null}'))
        self.assertTrue(r["present"])
        self.assertEqual(r["tracked_items"], 0)
        self.assertEqual(r["events_tracked"], 0)

    def test_full_mixed_aggregation(self):
        path = self.write_raw("full.json", """
        {"items":{"learning:a":{"kind":"learning","use_count":3,"last_used_at":"2026-06-10T00:00:00Z"},
                  "learning:b":{"kind":"learning","use_count":1,"last_used_at":"2026-06-20T00:00:00Z"},
                  "user:c":{"kind":"user","use_count":0},
                  "d":{"use_count":5,"last_used_at":"2026-06-01T00:00:00Z"}},
         "events":[{"kind":"recall","hit_count":2,"estimated_tokens":100,"at":"2026-06-10T00:00:00Z"},
                   {"kind":"recall","hit_count":3,"estimated_tokens":150,"at":"2026-06-15T00:00:00Z"},
                   {"kind":"history","hit_count":1,"estimated_tokens":50,"at":"2026-06-12T00:00:00Z"},
                   {"kind":"recall","hit_count":0,"at":null},
                   {"hit_count":7,"estimated_tokens":9}]}
        """)
        r = summaries.usage_summary_json(path)
        self.assertEqual(r["tracked_items"], 4)
        self.assertEqual(r["total_uses"], 9)
        self.assertEqual(r["last_used_at"], "2026-06-20T00:00:00Z")
        self.assertEqual(list(r["by_kind"].keys()), ["learning", "user", "unknown"])  # first-appearance
        self.assertEqual(r["by_kind"], {"learning": 2, "user": 1, "unknown": 1})
        self.assertEqual(r["events_tracked"], 5)
        self.assertEqual(list(r["by_event"].keys()), ["recall", "history", "unknown"])
        self.assertEqual(r["by_event"]["recall"],
                         {"writes": 3, "hits": 5, "estimated_tokens": 250, "last_at": "2026-06-15T00:00:00Z"})
        self.assertEqual(r["by_event"]["history"],
                         {"writes": 1, "hits": 1, "estimated_tokens": 50, "last_at": "2026-06-12T00:00:00Z"})
        self.assertEqual(r["by_event"]["unknown"],
                         {"writes": 1, "hits": 7, "estimated_tokens": 9, "last_at": None})
        self.assertEqual(r["economics"], {
            "recall_writes": 3, "history_writes": 1, "total_hit_count": 13,
            "estimated_output_tokens": 309, "last_event_at": "2026-06-15T00:00:00Z",
        })
        self.assertEqual(r["hot_items"], 2)   # use_count > 1: a(3), d(5)

    def test_output_key_order(self):
        r = summaries.usage_summary_json(self.write_raw("e.json", "{}"))
        self.assertEqual(list(r.keys()), list(self.ABSENT.keys()))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: FAIL - `AttributeError: module 'memory_router.summaries' has no attribute 'usage_summary_json'`.

- [ ] **Step 3: Extend `summaries.py`** - add the `_USAGE_PATH` constant (next to `_PROPOSALS_PATH`), `_max_present` (after `_jq_or`), and `_usage_absent` + `usage_summary_json` (at end of file):

```python
_USAGE_PATH = ".kimiflow/project/MEMORY-USAGE.json"
```

```python
def _max_present(values):
    # jq `[... // empty] | sort | last // null` (and the `// null` + select(!=null)
    # variant): keep values that are neither null nor false, sort, take the max;
    # null when nothing remains.
    kept = [v for v in values if v is not None and v is not False]
    return sorted(kept)[-1] if kept else None
```

```python
def _usage_absent():
    return {
        "present": False,
        "path": _USAGE_PATH,
        "tracked_items": 0,
        "total_uses": 0,
        "last_used_at": None,
        "by_kind": {},
        "events_tracked": 0,
        "by_event": {},
        "economics": {
            "recall_writes": 0,
            "history_writes": 0,
            "total_hit_count": 0,
            "estimated_output_tokens": 0,
            "last_event_at": None,
        },
        "hot_items": 0,
    }


def usage_summary_json(path):
    # Bash usage_summary_json (184-241): reads MEMORY-USAGE.json (a single object with
    # `.items` map + `.events` array). The Bash guard `[ ! -f ] || ! jq -e .` falls to
    # the absent shape when the file is missing, invalid JSON, or top-level null/false;
    # store.read_json returns None for missing/invalid and the literal for null. We also
    # treat a valid-but-non-object top level as absent (Bash jq-errors on `.items` there
    # -- unreachable for real MEMORY-USAGE.json; see plan).
    data = store.read_json(path)
    if not isinstance(data, dict):
        return _usage_absent()

    items = _jq_or(data.get("items"), {})
    events = _jq_or(data.get("events"), [])
    if not isinstance(items, dict):
        items = {}
    if not isinstance(events, list):
        events = []
    item_values = list(items.values())

    by_kind = {}
    for item in item_values:
        kind = _jq_or(item.get("kind"), "unknown")
        by_kind[kind] = by_kind.get(kind, 0) + 1

    by_event = {}
    for event in events:
        kind = _jq_or(event.get("kind"), "unknown")
        acc = by_event.get(kind)
        if acc is None:
            acc = {"writes": 0, "hits": 0, "estimated_tokens": 0, "last_at": None}
            by_event[kind] = acc
        acc["writes"] += 1
        acc["hits"] += _jq_or(event.get("hit_count"), 0)
        acc["estimated_tokens"] += _jq_or(event.get("estimated_tokens"), 0)
        # jq: .last_at = ([.last_at, (.at // null)] | map(select(. != null)) | sort | last // null)
        at = _jq_or(event.get("at"), None)
        acc["last_at"] = _max_present([acc["last_at"], at])

    def count_event_kind(value):
        return sum(1 for e in events if _jq_or(e.get("kind"), "") == value)

    return {
        "present": True,
        "path": _USAGE_PATH,
        "tracked_items": len(items),
        "total_uses": sum(_jq_or(i.get("use_count"), 0) for i in item_values),
        "last_used_at": _max_present([i.get("last_used_at") for i in item_values]),
        "by_kind": by_kind,
        "events_tracked": len(events),
        "by_event": by_event,
        "economics": {
            "recall_writes": count_event_kind("recall"),
            "history_writes": count_event_kind("history"),
            "total_hit_count": sum(_jq_or(e.get("hit_count"), 0) for e in events),
            "estimated_output_tokens": sum(_jq_or(e.get("estimated_tokens"), 0) for e in events),
            "last_event_at": _max_present([e.get("at") for e in events]),
        },
        "hot_items": sum(1 for i in item_values if _jq_or(i.get("use_count"), 0) > 1),
    }
```

- [ ] **Step 4: Run the focused tests**

Run: `cd hooks && python3 -m unittest memory_router.tests.test_summaries -v`
Expected: PASS - 21 tests (12 prior + 9 `UsageSummaryCase`).

- [ ] **Step 5: Full suite (no regression)**

Run: `export PATH="/opt/homebrew/bin:$PATH" && cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py'`
Expected: all green (185 tests: 176 prior + 9 new).

- [ ] **Step 6: Append spec §12 row** to `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md`:

```
| `usage_summary_json` non-object input | `jq -e .` passes for a valid non-object top level (e.g. `[1,2]`), then `.items` errors -> empty stdout (breaks the `--argjson` caller) | returns the absent shape | The port treats any non-dict parse as absent (more robust); `MEMORY-USAGE.json` is always an object, so this is unreachable. Missing / invalid / top-level null|false already map to absent in both. |
```

- [ ] **Step 7: Commit**

```bash
git add hooks/memory_router/summaries.py hooks/memory_router/tests/test_summaries.py docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md
git commit -m "feat(memory_router): usage_summary_json (MEMORY-USAGE.json aggregator)"
```

---

## Self-Review

**1. Spec coverage:** every Bash branch maps - the absent guard, `.items`/`.events` defaults, `total_uses` (`add // 0`), `last_used_at`/`last_event_at` (`// empty | sort | last`), `by_kind` (first-appearance reduce), `by_event` per-kind accumulation incl. `last_at` max with the `// null | select(!=null)` idiom, `economics` counts/sums, `hot_items` (`use_count > 1`), and exact key order (outer + `economics` + `by_event` sub-object). Reuses Plan-9 `_jq_or`; adds `_max_present` for the three shared max idioms.

**2. Empirical grounding (decisive):** the real Bash function was extracted and run on 8 fixtures (missing / invalid / literal null / literal false / `{}` / `items&events:null` / a full mixed object exercising every reduction + `last_at` max + economics + `hot_items` / a non-object array). Each Bash output normalized via `jq -c .` (key order preserved) and diffed against the Python `contracts.dumps`: **7/7 identical**; the 8th (non-object array) is the documented §12 divergence (Bash errors to empty; port returns absent).

**3. Placeholder scan:** complete code; no TBD; pure ASCII.

**4. Type consistency:** `usage_summary_json(path) -> dict`; `_max_present(list) -> value|None`; `_usage_absent() -> dict`. Serialization at the `contracts.dumps` boundary later.

## Notes for later plans (not part of this plan)
- **`economics_summary_json`** (243-364, ~122L) and **`global_efficiency_summary_json`** (483-597, ~115L): the large economics pipelines, each likely its own plan.
- **`learning_lifecycle_json`** (599-651) + **`learning_usefulness_json`** (653-712).
- **provider/vault subsystem**, then **`status_json`** (1399-1568) composing all summaries, then `cmd_status`, `curate`, `record`.
