#!/usr/bin/env bash
# kimiflow — unit tests for improvements-status.sh (workqueue close-back helper).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/improvements-status.sh"
LAUNCHER="$HERE/launcher-status.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — improvements-status uses jq for JSON"; exit 0
fi

reset_repo() {
  rm -rf "$REPO"; mkdir -p "$REPO/.kimiflow/project"
  git init -q "$REPO"
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name tester
  printf '.kimiflow/\n' > "$REPO/.gitignore"
  cat > "$REPO/.kimiflow/project/IMPROVEMENTS.md" <<'EOF'
# Improvements
## Priorisierte Slices

### 1. Release-Doku-Konsistenz automatischer machen
- Idee: foo

### 2. Hook-Doku synchronisieren
- Idee: bar

## Nicht-Ziele
- nix
EOF
  cat > "$REPO/.kimiflow/project/FINDINGS.md" <<'EOF'
# Findings
## Offen

### KF-F-001 - Beispiel-Finding
- Status: offen

## Erledigt / ueberholt
EOF
  git -C "$REPO" add -A; git -C "$REPO" commit -q -m base
}

run() { "$SCRIPT" "$@" --root "$REPO"; }

# --- AC-4: findings id is the explicit token kf-f-001, not a title slug ---
reset_repo
ids="$(run list --queue findings | awk -F'\t' '{print $1}')"
if [ "$ids" = "kf-f-001" ]; then pass "findings_id_is_token"; else fail "findings_id_is_token (got: $ids)"; fi

# --- AC-1: mark-done hides the slice from list ---
reset_repo
run mark-done release --commit abc123 --write >/dev/null
if run list | grep -q 'release-doku'; then fail "mark_done_hides (still listed)"; else pass "mark_done_hides"; fi
if grep -q 'kimiflow:queue-done id=release-doku-konsistenz-automatischer-machen commit=abc123' "$REPO/.kimiflow/project/IMPROVEMENTS.md"; then
  pass "mark_done_marker_written"; else fail "mark_done_marker_written"; fi

# --- AC-5: mark-done idempotent (single marker, commit updated) ---
reset_repo
run mark-done release --commit aaa --write >/dev/null
run mark-done release --commit bbb --write >/dev/null
n="$(grep -c 'kimiflow:queue-done' "$REPO/.kimiflow/project/IMPROVEMENTS.md")"
if [ "$n" = "1" ] && grep -q 'commit=bbb' "$REPO/.kimiflow/project/IMPROVEMENTS.md"; then
  pass "mark_done_idempotent"; else fail "mark_done_idempotent (markers=$n)"; fi

# --- AC-6: reopen removes the marker and the slice is listed again ---
reset_repo
run mark-done release --commit abc --write >/dev/null
run reopen release --write >/dev/null
if grep -q 'kimiflow:queue-done' "$REPO/.kimiflow/project/IMPROVEMENTS.md"; then
  fail "reopen_restores (marker remains)"
elif run list | grep -q 'release-doku'; then pass "reopen_restores"; else fail "reopen_restores (not relisted)"; fi

# --- AC-4: ambiguous prefix errors (non-zero, no write) ---
reset_repo
# add a 3rd slice sharing the 'hook-' prefix to force ambiguity with 'hook-doku'
python3 - "$REPO/.kimiflow/project/IMPROVEMENTS.md" <<'PY'
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("## Nicht-Ziele","### 3. Hook-Test extra\n- baz\n\n## Nicht-Ziele",1)
open(p,"w").write(s)
PY
before="$(md5 -q "$REPO/.kimiflow/project/IMPROVEMENTS.md" 2>/dev/null || md5sum "$REPO/.kimiflow/project/IMPROVEMENTS.md")"
if run mark-done hook --write >/dev/null 2>&1; then
  fail "ambiguous_prefix (should have failed)"
else
  after="$(md5 -q "$REPO/.kimiflow/project/IMPROVEMENTS.md" 2>/dev/null || md5sum "$REPO/.kimiflow/project/IMPROVEMENTS.md")"
  [ "$before" = "$after" ] && pass "ambiguous_prefix" || fail "ambiguous_prefix (file modified on error)"
fi

# --- AC-13: end-to-end — mark-done drops the launcher count by exactly 1 ---
reset_repo
if command -v jq >/dev/null 2>&1; then
  open0="$("$LAUNCHER" --root "$REPO" 2>/dev/null | jq -r '.improvements.open')"
  run mark-done release --commit abc --write >/dev/null
  open1="$("$LAUNCHER" --root "$REPO" 2>/dev/null | jq -r '.improvements.open')"
  if [ "$open0" = "2" ] && [ "$open1" = "1" ]; then pass "closeback_end_to_end"; else fail "closeback_end_to_end (open0=$open0 open1=$open1)"; fi
else
  echo "SKIP: closeback_end_to_end (jq)"
fi

# --- dry-run (no --write) does not modify the file ---
reset_repo
before="$(md5 -q "$REPO/.kimiflow/project/IMPROVEMENTS.md" 2>/dev/null || md5sum "$REPO/.kimiflow/project/IMPROVEMENTS.md")"
run mark-done release --commit abc >/dev/null
after="$(md5 -q "$REPO/.kimiflow/project/IMPROVEMENTS.md" 2>/dev/null || md5sum "$REPO/.kimiflow/project/IMPROVEMENTS.md")"
[ "$before" = "$after" ] && pass "dry_run_no_write" || fail "dry_run_no_write (file changed)"

# --- unknown queue errors ---
if run list --queue bogus >/dev/null 2>&1; then fail "unknown_queue_errors"; else pass "unknown_queue_errors"; fi

# --- R1 divergence: mutating explicit invalid roots fail closed ---
if "$SCRIPT" mark-done release --root "$REPO/missing-root" --write >/dev/null 2>&1; then
  fail "invalid_root_mutation_fails_closed"
else
  pass "invalid_root_mutation_fails_closed"
fi

if [ "$FAILS" -eq 0 ]; then echo "ALL PASS (improvements-status)"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
