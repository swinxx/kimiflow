#!/usr/bin/env bash
# Shared Bash helpers for the small kimiflow gates that remain shell-native.

kimiflow_state_value() {
  local state_file="$1" key="$2" key_lower
  [ -f "$state_file" ] || return 0
  key_lower="$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')"
  awk -v key="$key_lower" '
    {
      line = $0
      gsub(/\r/, "", line)
      gsub(/\*\*/, "", line)
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      lower = tolower(line)
      pattern = "^" key "[[:space:]]*:"
      if (lower ~ pattern) {
        sub(/^[^:]*:[[:space:]]*/, "", line)
        print line
        exit
      }
    }
  ' "$state_file"
}

kimiflow_resolve_root() {
  local root="$1"
  if [ -n "$root" ]; then
    (cd "$root" 2>/dev/null && pwd -P) || return 1
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd -P
  fi
}
