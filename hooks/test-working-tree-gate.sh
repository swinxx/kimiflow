#!/usr/bin/env bash
# kimiflow - unit tests for working-tree-gate.sh.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/working-tree-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

reset_repo() {
  rm -rf "$WORK/repo"
  git init -q "$WORK/repo"
  git -C "$WORK/repo" config user.email t@example.com
  git -C "$WORK/repo" config user.name tester
  printf 'base\n' > "$WORK/repo/file.txt"
  git -C "$WORK/repo" add file.txt
  git -C "$WORK/repo" commit -q -m base
}

field() {
  printf '%s\n' "$1" | awk -F '\t' -v n="$2" '{print $n}'
}

run_gate() {
  "$SCRIPT" --root "$WORK/repo"
}

assert_verdict() {
  local expected="$1" name="$2" out verdict
  out="$(run_gate)"
  verdict="$(field "$out" 2)"
  if [ "$verdict" = "$expected" ]; then
    pass "$name"
  else
    fail "$name"
    printf '%s\n' "$out"
  fi
}

assert_contains() {
  local text="$1" needle="$2" name="$3"
  if printf '%s\n' "$text" | grep -Fq -- "$needle"; then pass "$name"; else fail "$name (missing $needle in $text)"; fi
}

reset_repo
assert_verdict OPEN "clean_repo_opens"

reset_repo
mkdir -p "$WORK/repo/.kimiflow/session"
printf 'local state\n' > "$WORK/repo/.kimiflow/session/ACTIVE_RUN.json"
assert_verdict OPEN "kimiflow_state_ignored"

reset_repo
printf 'changed\n' > "$WORK/repo/file.txt"
out="$(run_gate)"
assert_contains "$out" $'WORKING_TREE_GATE\tCLOSED' "unstaged_change_closes"
assert_contains "$out" "unstaged=1" "unstaged_counted"

reset_repo
printf 'changed\n' > "$WORK/repo/file.txt"
git -C "$WORK/repo" add file.txt
out="$(run_gate)"
assert_contains "$out" $'WORKING_TREE_GATE\tCLOSED' "staged_change_closes"
assert_contains "$out" "staged=1" "staged_counted"

reset_repo
printf 'new\n' > "$WORK/repo/new.txt"
out="$(run_gate)"
assert_contains "$out" $'WORKING_TREE_GATE\tCLOSED' "untracked_change_closes"
assert_contains "$out" "untracked=1" "untracked_counted"
assert_contains "$out" "detail=new.txt" "dirty_detail_lists_path"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
