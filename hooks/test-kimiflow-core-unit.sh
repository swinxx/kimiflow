#!/usr/bin/env bash
# kimiflow — Python unit tests for kimiflow_core.
set -u

DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$DIR"
if python3 -m unittest discover -s kimiflow_core/tests -p 'test_*.py'; then
  echo "----"
  echo "ALL GREEN"
  exit 0
fi
echo "----"
echo "kimiflow_core unit tests failed"
exit 1
