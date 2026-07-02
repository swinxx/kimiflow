#!/usr/bin/env bash
# kimiflow — parity harness for the R1 kimiflow_core ports.
# It compares pre-R1 Bash helpers against the working tree, normalizing only known
# nondeterminism. Divergences must be documented in the R1 spec §12.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_SHA="${KIMIFLOW_CORE_PARITY_BASE_SHA:-72282e6}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

OLD_HOOKS="$WORK/old-hooks"
OLD_ROOT="$WORK/old-root"
mkdir -p "$OLD_ROOT"
if ! git -C "$ROOT" archive "$BASE_SHA" | tar -x -C "$OLD_ROOT"; then
  echo "cannot materialize $BASE_SHA" >&2
  exit 1
fi
OLD_HOOKS="$OLD_ROOT/hooks"

REPO="$WORK/repo"
HOME_DIR="$WORK/home"
mkdir -p "$REPO/hooks"
mkdir -p "$HOME_DIR"
git -C "$REPO" init -q
git -C "$REPO" config user.email "kimiflow@example.test"
git -C "$REPO" config user.name "Kimiflow Test"
printf 'hello\n' > "$REPO/README.md"
printf 'echo hi\n' > "$REPO/hooks/a.sh"
git -C "$REPO" add README.md hooks/a.sh
git -C "$REPO" commit -q -m init

FAILS=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'BAD  %s\n' "$1"; FAILS=$((FAILS + 1)); }

normalize() {
  sed -E \
    -e "s#$OLD_ROOT#ROOT#g" \
    -e "s#$ROOT#ROOT#g" \
    -e "s#$REPO#REPO#g" \
    -e "s#$WORK#WORK#g" \
    -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/TIMESTAMP/g' \
    -e 's/bh_[A-Za-z0-9_:-]+/bh_ID/g' \
    -e 's/[0-9a-f]{40}/COMMIT/g'
}

run_one() {
  local label="$1" script="$2" argstr="$3" old_script new_script diverged
  old_script="$OLD_HOOKS/$script"
  new_script="$ROOT/hooks/$script"
  args=()
  [ -n "$argstr" ] && IFS='|' read -r -a args <<< "$argstr"

  (cd "$REPO" && HOME="$HOME_DIR" KIMIFLOW_OBSIDIAN_URL= KIMIFLOW_OBSIDIAN_API_KEY= bash "$old_script" ${args[@]+"${args[@]}"}) > "$WORK/o.out" 2> "$WORK/o.err"; o_code=$?
  (cd "$REPO" && HOME="$HOME_DIR" KIMIFLOW_OBSIDIAN_URL= KIMIFLOW_OBSIDIAN_API_KEY= bash "$new_script" ${args[@]+"${args[@]}"}) > "$WORK/n.out" 2> "$WORK/n.err"; n_code=$?

  normalize < "$WORK/o.out" > "$WORK/o.out.norm"
  normalize < "$WORK/o.err" > "$WORK/o.err.norm"
  normalize < "$WORK/n.out" > "$WORK/n.out.norm"
  normalize < "$WORK/n.err" > "$WORK/n.err.norm"

  diverged=""
  [ "$o_code" != "$n_code" ] && diverged="${diverged}exit($o_code!=$n_code) "
  cmp -s "$WORK/o.out.norm" "$WORK/n.out.norm" || diverged="${diverged}stdout "
  cmp -s "$WORK/o.err.norm" "$WORK/n.err.norm" || diverged="${diverged}stderr "

  if [ -z "$diverged" ]; then
    ok "$label"
    return 0
  fi

  bad "$label — diverged: $diverged"
  if [ "$o_code" != "$n_code" ]; then
    printf '  exit codes: old=%s new=%s\n' "$o_code" "$n_code"
  fi
  if ! cmp -s "$WORK/o.out.norm" "$WORK/n.out.norm"; then
    printf '  [stdout diff]\n'
    diff -u "$WORK/o.out.norm" "$WORK/n.out.norm" | sed 's/^/  /' || true
  fi
  if ! cmp -s "$WORK/o.err.norm" "$WORK/n.err.norm"; then
    printf '  [stderr diff]\n'
    diff -u "$WORK/o.err.norm" "$WORK/n.err.norm" | sed 's/^/  /' || true
  fi
}

CASES=(
  "active_status_none::active-run.sh::status|--root|$REPO"
  "background_list_empty::background-run.sh::list|--root|$REPO|--json"
  "improvements_list_missing::improvements-status.sh::list|--root|$REPO"
  "project_map_status_missing::project-map-status.sh::status"
  "project_map_coverage_missing::project-map-status.sh::coverage|--affected|hooks/a.sh"
  "launcher_missing_root::launcher-status.sh::--root|$WORK/missing-root"
  "clarify_missing_dir::clarify-gate.sh::$WORK/missing-run"
  "plan_blocker_missing_dir::plan-blocker-gate.sh::$WORK/missing-run"
  "agentic_status_repo::agentic-readiness.sh::status|--root|$REPO"
)

for entry in "${CASES[@]}"; do
  label="${entry%%::*}"
  rest="${entry#*::}"
  script="${rest%%::*}"
  argstr="${rest#*::}"
  run_one "$label" "$script" "$argstr"
done

echo "----"
if [ "$FAILS" -eq 0 ]; then
  echo "ALL GREEN"
  exit 0
fi
echo "$FAILS DIVERGENCES"
exit 1
