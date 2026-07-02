# R1 Detail Plan: kimiflow_core + shared helper consolidation

**Date:** 2026-07-02 · **Branch:** `rebuild/r1-core` · **Status:** R1 plan audit clean (round 2: 2 auditors, `NONE`; no open BLOCKER/HIGH). Implementation may start with Commit R1.1.

**Goal:** Port the five large state/status scripts to a stdlib Python package (`hooks/kimiflow_core/`) behind thin Bash shims, while preserving every public CLI/hook contract through old-vs-new differential parity, existing suites, smokes, and release consistency.

## Hard constraints

- Python 3.9+ stdlib only. No new runtime dependency.
- Bash shims keep the current entrypoint paths and argv contracts.
- `memory_router` remains untouched except as a design precedent.
- No manual edits to `skills/kimiflow/SKILL.md`.
- Stage named paths only; no `git add -A` / `git add .`; no AI attribution.
- Every code commit gets: old-vs-new parity for touched script(s), affected `hooks/test-<name>.sh`, full discovered hook loop excluding `test-gate.sh`/`test-weakening-scan.sh`, both smokes, `release-consistency-check.sh`, and CHANGELOG Unreleased entry.
- Deliberate divergences are recorded in `docs/superpowers/specs/2026-07-02-kimiflow-core-rebuild-design.md` §12, a code comment at the implementation site, and the parity harness whitelist/expectation in the same commit.

## Current behavior inventory

### `resolve_root`

| Site | Current behavior | R1 decision |
|---|---|---|
| `active-run.sh` | explicit root: `cd "$root" && pwd`, else prints original root; implicit: `git rev-parse --show-toplevel` or logical `pwd` | Canonicalize |
| `background-run.sh` | same as `active-run.sh` | Canonicalize |
| `improvements-status.sh` | same as `active-run.sh` | Canonicalize |
| `launcher-status.sh` | accepts `--root`; invalid explicit roots produce JSON with `repo.present=false` rather than hard-failing | Preserve observational behavior |
| `agentic-readiness.sh` | explicit root: `cd "$root" && pwd -P` or hard-die; implicit: git root or physical `pwd -P` | Keep Bash, source shared helper |

Canonical R1 rule is mode-specific: mutating CLI commands use strict explicit-root resolution (`--root` must resolve or fail closed); read-only status/launcher paths preserve today's observational JSON/no-op behavior; hook payload `cwd` paths preserve today's hook-safe degradation to exit 0 on malformed cwd. Strict root behavior is a deliberate divergence for active/background/improvements invalid-root fallbacks and must be recorded in §12 with tests. Hook payload behavior is not changed.

### `state_value`

| Site | Current behavior | R1 decision |
|---|---|---|
| `active-run.sh` | strips CR, `**`, leading list marker; case-sensitive `Label:` match | Canonicalize |
| `launcher-status.sh` | same as `active-run.sh` | Canonicalize |
| `clarify-gate.sh` | strips CR, `**`, leading list marker; case-insensitive key match | Source shared Bash helper |
| `plan-blocker-gate.sh` | compact case-insensitive key match | Source shared Bash helper |

Canonical R1 rule: markdown-tolerant and case-insensitive key matching, first matching `key:` line wins, value is the text after the first colon. This is a deliberate divergence for active/launcher uppercase/lowercase STATE labels and must be recorded in the spec §12 table with tests.

Do not unify adjacent STATE-derived list parsers in R1. `launcher-status.sh` has a list-only `Affected files:` parser, while `active-run.sh` accepts inline/comma `Affected files:` and `Affected paths:` forms. Each port replicates its current parser exactly unless a later §12 row and parity update explicitly approve a change.

### Already-resolved baseline item

`state-gate.sh:61` currently matches the SKILL contract: small/lean/doc-only are not exempt; only trivial scope runs no gate. R1 treats this as a verified no-op unless a fresh repro proves drift.

## Target architecture

| Path | Responsibility |
|---|---|
| `hooks/kimiflow_core/__init__.py` | package marker |
| `hooks/kimiflow_core/contracts.py` | compact/pretty JSON output compatible with current jq shapes |
| `hooks/kimiflow_core/paths.py` | root resolution, relative paths, path validation |
| `hooks/kimiflow_core/state.py` | STATE.md parsing and canonical `state_value` |
| `hooks/kimiflow_core/atomic.py` | same-directory temp writes, explicit `0600` mode for private state, symlink refusal where current tests require it |
| `hooks/kimiflow_core/improvements_status.py` | port of `improvements-status.sh` |
| `hooks/kimiflow_core/project_map_status.py` | port of `project-map-status.sh` |
| `hooks/kimiflow_core/background_run.py` | port of `background-run.sh` |
| `hooks/kimiflow_core/launcher_status.py` | port of `launcher-status.sh` |
| `hooks/kimiflow_core/active_run.py` | port of `active-run.sh` |
| `hooks/kimiflow_core/tests/` | Python unit tests |
| `hooks/test-kimiflow-core-unit.sh` | `python3 -m unittest discover` wrapper |
| `hooks/test-kimiflow-core-parity.sh` | old-vs-new differential harness |
| `hooks/kimiflow-lib.sh` | shared Bash helper for remaining small Bash gates |

Thin shim pattern:

```bash
dir="$(cd "$(dirname "$0")" && pwd)"
exec env PYTHONPATH="$dir${PYTHONPATH:+:$PYTHONPATH}" python3 -m kimiflow_core.<entry> "$@"
```

## Differential parity strategy

- First implementation commit creates `hooks/test-kimiflow-core-parity.sh` while all five scripts are still Bash.
- The harness records `BASE_SHA=72282e6` (the pre-R1 code state) unless the first code commit deliberately refreshes it before any script changes.
- For each script, the harness materializes the old Bash script from `git show "$BASE_SHA:hooks/<script>.sh"` into a temp `old-hooks/` directory, copies required sibling scripts/packages as needed, then runs old vs working-tree command cases.
- Each case captures stdout, stderr, and exit code. Normalization masks nondeterministic fields only: temp roots, ISO timestamps, generated background IDs (`bh_...`), generated active item timestamps, and test repo commit hashes where old/new fixtures necessarily differ. A mismatch after normalization fails unless the case is explicitly listed as a §12 divergence with the expected new output.
- Case inventory starts from the existing shell tests and adds untested public CLI paths: `--help`/usage, malformed args, read-only vs `--write`, `--pretty`, missing `jq`, and hook stdin payload paths.
- Missing-`jq` is a contract, not an implementation accident: CLI subcommands that currently call `need_jq` continue to hard-fail with the existing error class when `jq` is absent, even if the Python implementation no longer needs jq internally. Hook entrypoints that currently degrade without jq (`active-run.sh prompt-context` / `stop-gate`) keep degrading to exit 0.

## Implementation sequence

### Commit R1.1 — Core foundation + parity harness, no cutover

- Add package skeleton, `contracts.py`, `paths.py`, `state.py`, `atomic.py`, unit wrapper, and differential parity harness.
- Add `docs/superpowers/specs/2026-07-02-kimiflow-core-rebuild-design.md` with §12 as the divergence ledger before any production cutover.
- Add Python unit tests for JSON formatting, root resolution, state parsing, and atomic writes.
- Add Python unit tests for the new canonical helper behavior, including strict invalid-root failures and case-insensitive STATE labels. Do not require production-script parity to show those divergences until the affected script's cutover commit records the §12 row and updates parity expectations.
- No production shim changes in this commit.

### Commit R1.2 — Port `improvements-status.sh`

- Port list/mark-done/reopen behavior.
- Preserve dry-run output and marker rewrite semantics.
- Existing suite: `hooks/test-improvements-status.sh`.
- Parity additions: unknown queue, dry-run, repeated mark/reopen, launcher count interaction.

### Commit R1.3 — Port `project-map-status.sh`

- Port status/coverage/refresh/index-symbols.
- Fix write safety for every mutating path, including `refresh --section`, `refresh --changed`, baseline updates, and public `index-symbols`: destination-directory `mkstemp`, explicit `0600`, `os.replace`, and honest failure paths that do not print `REFRESHED`/success after failed writes.
- Existing suite: `hooks/test-project-map-status.sh`.
- Add focused tests for failed temp write/install paths and file mode.

### Commit R1.4 — Port `background-run.sh`

- Port start/list/status/update/collect/cancel/mark-stale.
- Preserve candidate-only handling, symlink rejection, affected-path validation, and stale detection.
- Existing suite: `hooks/test-background-run.sh`.
- Parity additions: malformed ids, invalid files JSON, result tampering, terminal-status update refusal.

### Commit R1.5 — Port `launcher-status.sh`

- Port read-only snapshot assembly and compact/default vs `--full` serialization.
- Keep all caller contracts to active/background/memory/project-map helpers.
- Existing suite: `hooks/test-launcher-status.sh`.
- Parity additions: no `.kimiflow`, stale plugin cache, invalid map JSON, `--pretty`.

### Commit R1.6 — Port `active-run.sh`

- Port orchestrator commands plus `prompt-context` and `stop-gate` hook stdin behavior.
- Preserve learning review rollback, active session stale-risk handling, and no-jq degradation for hook entrypoints.
- Existing suite: `hooks/test-active-run.sh`.
- Parity additions: usage/malformed args, finish rollback paths, park/fail/abort, hook payload variants.

### Commit R1.7 — Shared Bash helper for remaining gates

- Add/source `hooks/kimiflow-lib.sh` in `clarify-gate.sh`, `plan-blocker-gate.sh`, and `agentic-readiness.sh` for canonical `state_value`/`resolve_root` where applicable.
- Keep scripts Bash 3.2-compatible.
- Old-vs-new parity covers all three public Bash gates before/after helper sourcing: `clarify-gate.sh`, `plan-blocker-gate.sh`, and `agentic-readiness.sh`.
- Existing suites: `hooks/test-clarify-gate.sh`, `hooks/test-plan-blocker-gate.sh`, `hooks/test-agentic-readiness.sh`, plus full loop.

## Verification loop per code commit

```bash
bash hooks/test-kimiflow-core-parity.sh
bash hooks/test-kimiflow-core-unit.sh
bash hooks/test-<ported-script>.sh
for t in hooks/test-*.sh; do
  case "$t" in hooks/test-gate.sh|hooks/test-weakening-scan.sh) continue ;; esac
  bash "$t" </dev/null
done
bash hooks/smoke-install.sh
bash hooks/smoke-install-codex.sh
bash hooks/release-consistency-check.sh
```

Run `bash docs/superpowers/plans/2026-07-02-invariant-check.sh` only if the commit touches SKILL.md/reference.md/phase or rendered host files; R1 should not.

## Audit questions for R1 plan reviewers

1. Does the differential parity harness make the byte-compatible contract enforceable enough before cutover?
2. Are the two deliberate semantic unifications (`resolve_root`, `state_value`) documented tightly enough for §12 and tests?
3. Is leaving `agentic-readiness.sh` in Bash while sourcing shared helpers safer than porting it in R1?
4. Does the Project Map write plan actually close the mode/atomicity/honest-failure findings?
