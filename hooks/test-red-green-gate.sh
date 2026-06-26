#!/usr/bin/env bash
# kimiflow - unit tests for red-green-gate.sh.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/red-green-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }

write_state() {
  local dir="$1" mode="$2"
  mkdir -p "$dir"
  printf 'Status: active\nMode: %s\nAffected files: src/demo.js\n' "$mode" > "$dir/STATE.md"
}

assert_gate() {
  local dir="$1" expected="$2" name="$3" out verdict
  out="$("$SCRIPT" "$dir")"
  verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
  if [ "$verdict" = "$expected" ]; then
    pass "$name"
  else
    fail "$name"
    printf '%s\n' "$out"
  fi
}

feature="$WORK/feature"
write_state "$feature" feature
assert_gate "$feature" OPEN "non_fix_mode_is_not_required"

missing="$WORK/missing"
write_state "$missing" fix
assert_gate "$missing" CLOSED "fix_missing_bug_repro_closes"

only_green="$WORK/only-green"
write_state "$only_green" fix
cat > "$only_green/BUG-REPRO.md" <<'EOF'
# Bug reproduction
Green command: npm test
Green status: passed
Regression command: npm test
Regression status: passed
EOF
assert_gate "$only_green" CLOSED "green_without_red_closes"

red_passed="$WORK/red-passed"
write_state "$red_passed" fix
cat > "$red_passed/BUG-REPRO.md" <<'EOF'
# Bug reproduction
Red command: npm test -- bug.spec
Red status: passed
Red output: bug not reproduced.
Green command: npm test -- bug.spec
Green status: passed
Green output: bug.spec passed.
Regression command: npm test
Regression status: passed
EOF
assert_gate "$red_passed" CLOSED "red_must_actually_fail"

missing_output="$WORK/missing-output"
write_state "$missing_output" fix
cat > "$missing_output/BUG-REPRO.md" <<'EOF'
# Bug reproduction
Red command: npm test -- bug.spec
Red status: failed
Green command: npm test -- bug.spec
Green status: passed
Regression command: npm test
Regression status: passed
EOF
out="$("$SCRIPT" "$missing_output")"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && printf '%s\n' "$detail" | grep -q 'red_output_missing' && printf '%s\n' "$detail" | grep -q 'green_output_missing'; then
  pass "missing_red_green_output_closes"
else
  fail "missing_red_green_output_closes"
  printf '%s\n' "$out"
fi

valid="$WORK/valid"
write_state "$valid" fix
cat > "$valid/BUG-REPRO.md" <<'EOF'
# Bug reproduction
Red command: npm test -- bug.spec
Red status: failed
Red output: reproduced the reported hang.
Green command: npm test -- bug.spec
Green status: passed
Green output: bug.spec passed.
Regression command: npm test
Regression status: passed
EOF
assert_gate "$valid" OPEN "valid_red_green_regression_opens"

markdown="$WORK/markdown"
mkdir -p "$markdown"
cat > "$markdown/STATE.md" <<'EOF'
- **Status:** active
- **Mode:** fix
- **Affected files:** src/demo.js
EOF
cat > "$markdown/BUG-REPRO.md" <<'EOF'
# Bug reproduction
- Red command: pytest tests/test_bug.py
- Red result: exit code 1
- Red output: reproduced missing API response.
- Green command: pytest tests/test_bug.py
- Green result: exit code 0
- Green output: test passes with expected response.
- Regression status: not applicable
- Regression reason: focused fix has no broader regression suite in this fixture.
EOF
assert_gate "$markdown" OPEN "markdown_state_and_regression_na_open"

na_without_reason="$WORK/na-without-reason"
write_state "$na_without_reason" fix
cat > "$na_without_reason/BUG-REPRO.md" <<'EOF'
Red command: pytest tests/test_bug.py
Red status: failed
Red output: reproduced.
Green command: pytest tests/test_bug.py
Green status: passed
Green output: fixed.
Regression status: not applicable
EOF
out="$("$SCRIPT" "$na_without_reason")"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && printf '%s\n' "$detail" | grep -q 'regression_na_reason_missing'; then
  pass "regression_na_without_reason_closes"
else
  fail "regression_na_without_reason_closes"
  printf '%s\n' "$out"
fi

override="$WORK/override"
mkdir -p "$override"
printf 'Status: active\nMode: feature\n' > "$override/STATE.md"
cat > "$override/BUG-REPRO.md" <<'EOF'
Red command: pytest tests/test_bug.py
Red status: failed
Red output: reproduced.
Green command: pytest tests/test_bug.py
Green status: passed
Green output: fixed.
Regression command: pytest
Regression status: passed
EOF
out="$("$SCRIPT" "$override" --mode fix)"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
if [ "$verdict" = "OPEN" ]; then pass "mode_override_fix_open"; else fail "mode_override_fix_open"; printf '%s\n' "$out"; fi

out="$("$SCRIPT" "$override" --mode)"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && [ "$detail" = "detail=missing_mode_value" ]; then
  pass "missing_mode_value_closes"
else
  fail "missing_mode_value_closes"
  printf '%s\n' "$out"
fi

out="$("$SCRIPT" "$override" --mode --pretty)"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && [ "$detail" = "detail=missing_mode_value" ]; then
  pass "mode_flag_value_closes"
else
  fail "mode_flag_value_closes"
  printf '%s\n' "$out"
fi

out="$("$SCRIPT" "$override" --mode nonsense)"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && [ "$detail" = "detail=invalid_mode=nonsense" ]; then
  pass "invalid_explicit_mode_closes"
else
  fail "invalid_explicit_mode_closes"
  printf '%s\n' "$out"
fi

wrong_order="$WORK/wrong-order"
write_state "$wrong_order" fix
cat > "$wrong_order/BUG-REPRO.md" <<'EOF'
# Bug reproduction
Green command: npm test -- bug.spec
Green status: passed
Green output: passed too early.
Red command: npm test -- bug.spec
Red status: failed
Red output: failed after green evidence.
Regression command: npm test
Regression status: passed
EOF
out="$("$SCRIPT" "$wrong_order")"
verdict="$(printf '%s\n' "$out" | awk -F '\t' '{print $2}')"
detail="$(printf '%s\n' "$out" | awk -F '\t' '{print $5}')"
if [ "$verdict" = "CLOSED" ] && printf '%s\n' "$detail" | grep -q 'red_green_order_invalid'; then
  pass "green_before_red_closes"
else
  fail "green_before_red_closes"
  printf '%s\n' "$out"
fi

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
