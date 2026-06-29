"""Global (cross-project, local-anonymous) metrics location + enablement helpers.
Ports of the Bash global_metrics_enabled / global_metrics_base_dir /
global_metrics_display_path @ kimiflow--v0.1.50 (366-385). The record/purge infra
(salt, project_id, append) lands with the `metrics --global` subcommand."""
import os

# Bash `case "$KIMIFLOW_GLOBAL_METRICS" in off|OFF|0|false|FALSE|no|NO) return 1`.
_DISABLED = {"off", "OFF", "0", "false", "FALSE", "no", "NO"}


def enabled():
    # Bash global_metrics_enabled: KIMIFLOW_GLOBAL_METRICS (default "on" when unset OR
    # empty); only these exact off/0/false/no spellings disable it (anything else -> on).
    value = os.environ.get("KIMIFLOW_GLOBAL_METRICS", "on")
    return value not in _DISABLED


def base_dir():
    # Bash global_metrics_base_dir: KIMIFLOW_HOME, else HOME/.kimiflow; None (Bash
    # `return 1`) when neither yields a usable base or the base is empty / "/".
    base = os.environ.get("KIMIFLOW_HOME", "")
    if not base:
        home = os.environ.get("HOME", "")
        if not home:
            return None
        base = home + "/.kimiflow"
    if not base or base == "/":
        return None
    return base + "/metrics"


def display_path():
    # Bash global_metrics_display_path: the fixed user-facing path.
    return "~/.kimiflow/metrics/token-economics.jsonl"
