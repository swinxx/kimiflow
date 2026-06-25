#!/usr/bin/env bash
# kimiflow — unit tests for project-map-status.sh.
# Isolation: temp git repo under mktemp; the real repo is never touched.
set -u

SCRIPT="$(cd "$(dirname "$0")" && pwd)/project-map-status.sh"
WORK="$(mktemp -d)"
REPO="$WORK/repo"
INDEX="$REPO/.kimiflow/project/INDEX.json"
trap 'rm -rf "$WORK"' EXIT

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS + 1)); }
assert_has() { case "$1" in *"$2"*) pass "$3" ;; *) fail "$3 (missing '$2' in: $1)" ;; esac; }
assert_eq() { if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1' want '$2')"; fi; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed — project-map-status uses jq"; exit 0
fi

hash_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print "sha256:" $1}'
  else
    sha256sum "$1" | awk '{print "sha256:" $1}'
  fi
}

reset_repo() {
  rm -rf "$REPO"
  mkdir -p "$REPO/hooks" "$REPO/docs" "$REPO/.kimiflow/project"
  ( cd "$REPO" && git init -q && git config user.email "kimiflow@example.test" && git config user.name "kimiflow test" )
  printf 'one\n' > "$REPO/hooks/a.sh"
  printf 'guide\n' > "$REPO/docs/guide.md"
  ( cd "$REPO" && git add hooks/a.sh docs/guide.md && git commit -q -m init )
}

write_index() {
  local base="$1"
  local hook_hash="$2"
  local docs_hash="$3"
  jq -n \
    --arg base "$base" \
    --arg hook_hash "$hook_hash" \
    --arg docs_hash "$docs_hash" \
    '{
      schema_version: 1,
      language: "de",
      scan_depth: "standard",
      baseline_commit: $base,
      created_at: "2026-06-25T00:00:00Z",
      sections: {
        hooks: {
          files: ["hooks/a.sh"],
          prefixes: ["hooks/"],
          file_hashes: {"hooks/a.sh": $hook_hash},
          last_scanned_commit: $base,
          status: "current"
        },
        docs: {
          files: ["docs/guide.md"],
          prefixes: ["docs/"],
          file_hashes: {"docs/guide.md": $docs_hash},
          last_scanned_commit: $base,
          status: "stale"
        },
        tech: {
          files: ["package.json"],
          prefixes: ["."],
          file_hashes: {},
          last_scanned_commit: $base,
          status: "current"
        }
      },
      artifacts: {}
    }' > "$INDEX"
}

run_status() {
  ( cd "$REPO" && "$SCRIPT" status "$@" )
}

run_refresh() {
  ( cd "$REPO" && "$SCRIPT" refresh "$@" )
}

run_coverage() {
  ( cd "$REPO" && "$SCRIPT" coverage "$@" )
}

# missing index
reset_repo
rm -f "$INDEX"
out="$(run_status)"
assert_has "$out" $'PROJECT_MAP\tmissing' "missing_index_reports_missing"
out="$(run_coverage --affected hooks/a.sh)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tmissing' "missing_index_coverage_reports_missing"
assert_has "$out" 'phase2_depth=full' "missing_index_coverage_uses_full_depth"

# current section from matching hashes
reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
write_index "$BASE" "$(hash_file "$REPO/hooks/a.sh")" "$(hash_file "$REPO/docs/guide.md")"
out="$(run_status)"
assert_has "$out" $'SECTION\thooks\tcurrent' "matching_hash_reports_current"
out="$(run_coverage --affected hooks/a.sh)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tcovered' "coverage_reports_current_affected_path_covered"
assert_has "$out" 'phase2_depth=compressed' "coverage_current_path_uses_compressed_phase2"
tmp_index="$(mktemp)"
jq '.sections.empty = {status: "current"}' "$INDEX" > "$tmp_index" && mv "$tmp_index" "$INDEX"
out="$(run_coverage --affected hooks/a.sh)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tcovered' "coverage_ignores_unrelated_unknown_section"
assert_has "$out" 'phase2_depth=compressed' "coverage_unrelated_unknown_keeps_compressed_phase2"

# exact hash mismatch marks that section stale
printf 'two\n' > "$REPO/hooks/a.sh"
out="$(run_status --affected hooks/a.sh)"
assert_has "$out" $'PROJECT_MAP\tpartially_stale' "hash_mismatch_makes_map_partially_stale"
assert_has "$out" $'SECTION\thooks\tstale\taffected=yes\treason=hash-mismatch' "hash_mismatch_section_stale"
assert_has "$out" 'affected_stale=1' "affected_stale_counted"
out="$(run_coverage --affected hooks/a.sh)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tstale' "coverage_marks_stale_affected_path"
assert_has "$out" 'phase2_depth=targeted' "coverage_stale_path_uses_targeted_phase2"

# new file under a known prefix is only potentially stale
reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
write_index "$BASE" "$(hash_file "$REPO/hooks/a.sh")" "$(hash_file "$REPO/docs/guide.md")"
printf 'new\n' > "$REPO/hooks/new.sh"
out="$(run_status)"
assert_has "$out" $'SECTION\thooks\tpotentially_stale' "new_file_under_prefix_potentially_stale"
out="$(run_coverage --affected outside/new.txt)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tpartial' "coverage_marks_unmapped_affected_path"
assert_has "$out" 'phase2_depth=full' "coverage_unmapped_path_uses_full_phase2"

# manifest/build config change fans out to stack-ish sections
reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
write_index "$BASE" "$(hash_file "$REPO/hooks/a.sh")" "$(hash_file "$REPO/docs/guide.md")"
printf '{"scripts":{"test":"true"}}\n' > "$REPO/package.json"
out="$(run_status)"
assert_has "$out" $'SECTION\ttech\tpotentially_stale' "manifest_change_marks_stackish_section_potentially_stale"

# refresh updates only selected sections
reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
write_index "$BASE" "$(hash_file "$REPO/hooks/a.sh")" "$(hash_file "$REPO/docs/guide.md")"
printf 'two\n' > "$REPO/hooks/a.sh"
out="$(run_refresh --section hooks)"
assert_has "$out" $'REFRESHED\thooks\tfiles=1' "refresh_reports_selected_section"
assert_eq "$(jq -r '.sections.hooks.status' "$INDEX")" "current" "refresh_marks_selected_section_current"
assert_eq "$(jq -r '.sections.docs.status' "$INDEX")" "stale" "refresh_leaves_other_section_status_alone"
assert_eq "$(jq -r '.sections.hooks.file_hashes["hooks/a.sh"]' "$INDEX")" "$(hash_file "$REPO/hooks/a.sh")" "refresh_updates_hash"

# no section files/hashes is unknown, not silently current
reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
jq -n --arg base "$BASE" '{
  schema_version: 1,
  language: "de",
  scan_depth: "standard",
  baseline_commit: $base,
  created_at: "2026-06-25T00:00:00Z",
  sections: {empty: {status: "current"}},
  artifacts: {}
}' > "$INDEX"
out="$(run_status)"
assert_has "$out" $'SECTION\tempty\tunknown' "empty_section_unknown"

reset_repo
BASE="$(cd "$REPO" && git rev-parse --short HEAD)"
write_index "$BASE" "$(hash_file "$REPO/hooks/a.sh")" "$(hash_file "$REPO/docs/guide.md")"
tmp_index="$(mktemp)"
jq '.sections.mystery = {prefixes: ["mystery/"], last_scanned_commit: "NOT VERIFIED", status: "current"}' "$INDEX" > "$tmp_index" && mv "$tmp_index" "$INDEX"
out="$(run_coverage --affected mystery/new.txt)"
assert_has "$out" $'PROJECT_MAP_COVERAGE\tunknown' "coverage_marks_affected_unknown_section"
assert_has "$out" 'affected_unknown=1' "coverage_counts_affected_unknown_section"
assert_has "$out" 'phase2_depth=targeted' "coverage_affected_unknown_uses_targeted_phase2"

echo "----"
if [ "$FAILS" -eq 0 ]; then echo "ALL GREEN"; exit 0; else echo "$FAILS FAILED"; exit 1; fi
