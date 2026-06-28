#!/usr/bin/env bash
# kimiflow — unit tests for improvements-staleness-nudge.sh (Stop-hook workqueue close-back nudge).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/improvements-staleness-nudge.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
trap 'rm -rf "$WORK"' EXIT
export KIMIFLOW_PLUGIN_ROOT="$HERE/.."

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — nudge uses jq"; exit 0
fi

reset_repo() {
  rm -rf "$REPO"; mkdir -p "$REPO/.kimiflow/project"
  git init -q "$REPO"
  printf '## Priorisierte Slices\n\n### 1. Foo offen\n- x\n\n## Nicht-Ziele\n' > "$REPO/.kimiflow/project/IMPROVEMENTS.md"
  printf '## Offen\n\nKeine.\n' > "$REPO/.kimiflow/project/FINDINGS.md"
}
# Real STATE.md uses a PLAIN run-level status line ("Status: done", no bullet) — active-run.sh writes it that way.
add_done_run() { mkdir -p "$REPO/.kimiflow/$1"; printf 'Status: done\n- Phase 7: done\n' > "$REPO/.kimiflow/$1/STATE.md"; }
run_hook() { printf '{"cwd":"%s","stop_hook_active":%s}' "$REPO" "${1:-false}" | bash "$HOOK"; }

# --- AC-8: stop_hook_active=true → silent (loop-break) ---
reset_repo; add_done_run run-a
out="$(run_hook true)"
[ -z "$out" ] && pass "loop_break" || fail "loop_break (emitted: $out)"

# --- seed: first Stop without a stamp → silent + stamp written (B#2) ---
reset_repo; add_done_run run-a
out="$(run_hook)"
if [ -z "$out" ] && [ -f "$REPO/.kimiflow/.improvements-nudge-stamp" ]; then pass "seed_no_fire"; else fail "seed_no_fire (out=$out)"; fi

# --- AC-7: silent when no new done-run since stamp ---
out="$(run_hook)"
[ -z "$out" ] && pass "silent_no_new_run" || fail "silent_no_new_run (emitted: $out)"

# --- AC-7: fires once on a new done-run with an open slice ---
add_done_run run-b
out="$(run_hook)"
if printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "Stop" and (.systemMessage|length>0)' >/dev/null 2>&1; then
  pass "fires_on_new_done_run"; else fail "fires_on_new_done_run (out=$out)"; fi

# --- rate-limit: a NEW done-run the SAME day after a fire → still silent (already_fired_today, not just no-increase) ---
add_done_run run-c
out="$(run_hook)"
[ -z "$out" ] && pass "rate_limited_same_day" || fail "rate_limited_same_day (emitted: $out)"

# --- AC-7: silent when 0 open slices, even with a new done-run ---
reset_repo
# no open slices: empty Priorisierte Slices
printf '## Priorisierte Slices\n\n## Nicht-Ziele\n' > "$REPO/.kimiflow/project/IMPROVEMENTS.md"
add_done_run run-a
run_hook >/dev/null            # seed
add_done_run run-b
out="$(run_hook)"
[ -z "$out" ] && pass "silent_none" || fail "silent_none (emitted: $out)"

# --- AC-8: graceful without a repo / queue file → exit 0, silent ---
EMPTY="$WORK/empty"; mkdir -p "$EMPTY"
out="$(printf '{"cwd":"%s","stop_hook_active":false}' "$EMPTY" | bash "$HOOK")"
rc=$?
[ -z "$out" ] && [ "$rc" = "0" ] && pass "graceful_no_repo" || fail "graceful_no_repo (rc=$rc out=$out)"

# --- AC-8: no jq on PATH → exit 0, silent ---
reset_repo; add_done_run run-a
out="$(PATH="" "$BASH" "$HOOK" < /dev/null)"; rc=$?
[ -z "$out" ] && [ "$rc" = "0" ] && pass "no_jq" || fail "no_jq (rc=$rc out=$out)"

if [ "$FAILS" -eq 0 ]; then echo "ALL PASS (improvements-staleness-nudge)"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
