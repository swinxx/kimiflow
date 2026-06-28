#!/usr/bin/env bash
# kimiflow — local workqueue close-back helper.
#
# Marks slices in the local workqueues as done so the launcher stops counting them open.
# Canonical done-state = an in-place marker line directly under the slice heading:
#   <!-- kimiflow:queue-done id=<id> commit=<sha> date=<YYYY-MM-DD> -->
# The launcher's count_section_items skips any open-section block carrying this marker.
#
# Commands:
#   improvements-status.sh list      [--queue improvements|findings] [--root <path>] [--json|--pretty]
#   improvements-status.sh mark-done <id> [--queue ...] [--commit <sha>] [--root <path>] [--write]
#   improvements-status.sh reopen    <id> [--queue ...] [--root <path>] [--write]
#
# Queues: improvements -> .kimiflow/project/IMPROVEMENTS.md (open section "## Priorisierte Slices"/"## Prioritized Slices")
#         findings     -> .kimiflow/project/FINDINGS.md      (open section "## Offen"/"## Open")
# Slice id: explicit token (e.g. KF-F-001 -> kf-f-001) if the heading starts with one, else a title slug.
# list is read-only; mark-done/reopen need --write to persist (else dry-run). Atomic write (mktemp + mv -f).
set -u

MARKER_SUBSTR='kimiflow:queue-done'

usage() { sed -n '1,18p' "$0" >&2; }
die() { printf 'improvements-status: %s\n' "$1" >&2; exit "${2:-1}"; }

iso_date() { date -u +%Y-%m-%d; }

resolve_root() {
  local root="$1"
  if [ -n "$root" ]; then
    (cd "$root" 2>/dev/null && pwd) || printf '%s' "$root"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

queue_file() {
  case "$1" in
    improvements) printf '.kimiflow/project/IMPROVEMENTS.md' ;;
    findings)     printf '.kimiflow/project/FINDINGS.md' ;;
    *) die "unknown queue: $1 (use improvements|findings)" 2 ;;
  esac
}

queue_section_re() {
  case "$1" in
    improvements) printf '^##[[:space:]]+(Priorisierte Slices|Prioritized Slices)([[:space:]].*)?$' ;;
    findings)     printf '^##[[:space:]]+(Offen|Open)([[:space:]].*)?$' ;;
  esac
}

# Emit one TSV line per slice in the open section: "<id>\t<marked 0|1>\t<title>"
list_slices() {
  local file="$1" sec_re="$2"
  [ -f "$file" ] || return 0
  awk -v sec_re="$sec_re" -v marker="$MARKER_SUBSTR" '
    function deriveid(line,   t, id) {
      if (match(line, /^([A-Za-z]+-[A-Za-z]+-[0-9]+|[A-Za-z]+-[0-9]+)/)) {
        return tolower(substr(line, RSTART, RLENGTH))
      }
      t = line
      sub(/^[0-9]+\.[[:space:]]*/, "", t)
      sub(/^[-*][[:space:]]*/, "", t)
      id = tolower(t)
      gsub(/[^a-z0-9]+/, "-", id)
      gsub(/^-+/, "", id); gsub(/-+$/, "", id)
      return id
    }
    function emit() { if (have) printf "%s\t%d\t%s\n", id, marked, title }
    $0 ~ sec_re { insec = 1; next }
    insec && /^## / { emit(); have = 0; insec = 0; next }
    insec && /^### / {
      emit()
      have = 1; marked = 0
      hl = $0; sub(/^###[[:space:]]+/, "", hl)
      title = hl
      id = deriveid(hl)
      next
    }
    insec && have && index($0, marker) > 0 { marked = 1 }
    END { if (insec) emit() }
  ' "$file"
}

cmd_list() {
  local queue="$1" root="$2" fmt="$3"
  local file sec_re slices
  file="$(queue_file "$queue")"
  sec_re="$(queue_section_re "$queue")"
  slices="$(list_slices "$root/$file" "$sec_re")"
  # open = slices without marker (field2 == 0)
  local open
  open="$(printf '%s\n' "$slices" | awk -F'\t' 'NF>=3 && $2==0')"
  local count
  count="$(printf '%s' "$open" | grep -c '' )"
  [ -n "$open" ] || count=0
  case "$fmt" in
    json)
      if command -v jq >/dev/null 2>&1; then
        printf '%s\n' "$open" | awk -F'\t' 'NF>=3{print $1"\t"$3}' \
          | jq -R -s --arg q "$queue" 'split("\n") | map(select(length>0) | split("\t") | {id: .[0], title: .[1]}) | {queue: $q, count: length, open: .}'
      else
        printf '{"queue":"%s","count":%s,"open":[]}\n' "$queue" "$count"
      fi
      ;;
    pretty)
      if [ "$count" -eq 0 ]; then
        printf 'queue %s: keine offenen Slices.\n' "$queue"
      else
        printf 'queue %s: %s offen\n' "$queue" "$count"
        printf '%s\n' "$open" | awk -F'\t' 'NF>=3{printf "  - %-40s %s\n", $1, $3}'
      fi
      ;;
    *)
      printf '%s\n' "$open" | awk -F'\t' 'NF>=3{print $1"\t"$3}'
      ;;
  esac
}

# Resolve an id by exact match or unique prefix among the given candidate id list (newline-separated).
# Prints the resolved id on stdout; on ambiguity/not-found prints an error to stderr and returns non-zero.
resolve_id() {
  local want="$1" candidates="$2"
  local exact
  exact="$(printf '%s\n' "$candidates" | awk -v w="$want" 'NF && $0==w')"
  if [ -n "$exact" ]; then printf '%s' "$want"; return 0; fi
  local matches
  matches="$(printf '%s\n' "$candidates" | awk -v w="$want" 'NF && index($0, w)==1')"
  local n
  n="$(printf '%s\n' "$matches" | grep -c '[^[:space:]]')"
  if [ "$n" -eq 1 ]; then printf '%s' "$(printf '%s\n' "$matches" | awk 'NF{print; exit}')"; return 0; fi
  if [ "$n" -eq 0 ]; then printf 'id not found: %s\n' "$want" >&2; return 1; fi
  { printf 'ambiguous id prefix "%s" matches:\n' "$want"; printf '%s\n' "$matches" | sed 's/^/  - /'; } >&2
  return 1
}

# Rewrite the file: in the open section, for the block whose id == target, drop any existing marker line and
# (for action=mark) insert a fresh marker right under the heading. action=reopen only drops.
rewrite_block() {
  local file="$1" sec_re="$2" target="$3" action="$4" newmarker="$5"
  awk -v sec_re="$sec_re" -v target="$target" -v action="$action" -v newmarker="$newmarker" -v marker="$MARKER_SUBSTR" '
    function deriveid(line,   t, id) {
      if (match(line, /^([A-Za-z]+-[A-Za-z]+-[0-9]+|[A-Za-z]+-[0-9]+)/)) {
        return tolower(substr(line, RSTART, RLENGTH))
      }
      t = line
      sub(/^[0-9]+\.[[:space:]]*/, "", t)
      sub(/^[-*][[:space:]]*/, "", t)
      id = tolower(t)
      gsub(/[^a-z0-9]+/, "-", id)
      gsub(/^-+/, "", id); gsub(/-+$/, "", id)
      return id
    }
    $0 ~ sec_re { insec = 1; intarget = 0; print; next }
    insec && /^## / { insec = 0; intarget = 0; print; next }
    insec && /^### / {
      hl = $0; sub(/^###[[:space:]]+/, "", hl)
      cur = deriveid(hl)
      print
      if (cur == target) {
        intarget = 1
        if (action == "mark") print newmarker
      } else {
        intarget = 0
      }
      next
    }
    insec && intarget && index($0, marker) > 0 { next }
    { print }
  ' "$file"
}

atomic_write() {
  local file="$1" content="$2"
  local dir tmp
  dir="$(dirname "$file")"
  tmp="$(mktemp "$dir/.iqs.tmp.XXXXXX")" || die "cannot create temp file" 1
  # command substitution stripped the trailing newline(s); restore exactly one so the file stays newline-terminated.
  printf '%s\n' "$content" > "$tmp" || { rm -f "$tmp"; die "cannot write temp file" 1; }
  mv -f "$tmp" "$file" || { rm -f "$tmp"; die "cannot install $file" 1; }
}

cmd_change() {
  local action="$1" id_arg="$2" queue="$3" root="$4" commit="$5" write="$6"
  [ -n "$id_arg" ] || { usage; die "$action needs an <id>" 2; }
  local file sec_re path slices candidates
  file="$(queue_file "$queue")"
  sec_re="$(queue_section_re "$queue")"
  path="$root/$file"
  [ -f "$path" ] || die "queue file not found: $file" 1
  slices="$(list_slices "$path" "$sec_re")"
  if [ "$action" = "reopen" ]; then
    candidates="$(printf '%s\n' "$slices" | awk -F'\t' 'NF>=3 && $2==1 {print $1}')"
  else
    candidates="$(printf '%s\n' "$slices" | awk -F'\t' 'NF>=3 {print $1}')"
  fi
  local target
  target="$(resolve_id "$id_arg" "$candidates")" || exit 1

  local newmarker=""
  if [ "$action" = "mark" ]; then
    [ -n "$commit" ] || commit="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || printf 'NONE')"
    # Sanitize commit to a safe charset so it cannot break the marker line or the awk -v that carries it
    # (awk -v interprets backslash escapes; a newline/backslash would split the single-line marker).
    commit="$(printf '%s' "$commit" | tr -cd '0-9A-Za-z._-')"
    [ -n "$commit" ] || commit="NONE"
    newmarker="<!-- ${MARKER_SUBSTR} id=${target} commit=${commit} date=$(iso_date) -->"
  fi

  local newcontent
  newcontent="$(rewrite_block "$path" "$sec_re" "$target" "$action" "$newmarker")"

  if [ "$write" -eq 1 ]; then
    atomic_write "$path" "$newcontent"
    if [ "$action" = "mark" ]; then
      printf 'marked done: %s (%s) in %s\n' "$target" "$queue" "$file"
    else
      printf 'reopened: %s (%s) in %s\n' "$target" "$queue" "$file"
    fi
  else
    printf 'DRY-RUN (%s %s in %s) — re-run with --write to persist.\n' "$action" "$target" "$queue"
  fi
}

main() {
  local cmd="${1:-}"; shift || true
  local queue="improvements" root="" commit="" write=0 fmt="text" id_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --queue) queue="${2:-}"; shift 2 ;;
      --root) root="${2:-}"; shift 2 ;;
      --commit) commit="${2:-}"; shift 2 ;;
      --write) write=1; shift ;;
      --json) fmt="json"; shift ;;
      --pretty) fmt="pretty"; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) die "unknown flag: $1" 2 ;;
      *) [ -z "$id_arg" ] && id_arg="$1" || die "unexpected argument: $1" 2; shift ;;
    esac
  done
  case "$queue" in improvements|findings) ;; *) die "unknown queue: $queue (use improvements|findings)" 2 ;; esac
  root="$(resolve_root "$root")"

  case "$cmd" in
    list)      cmd_list "$queue" "$root" "$fmt" ;;
    mark-done) cmd_change mark "$id_arg" "$queue" "$root" "$commit" "$write" ;;
    reopen)    cmd_change reopen "$id_arg" "$queue" "$root" "" "$write" ;;
    ""|-h|--help) usage; exit 0 ;;
    *) usage; die "unknown command: $cmd" 2 ;;
  esac
}

main "$@"
