# kimiflow_core rebuild design

**Date:** 2026-07-02 · **Scope:** R1 Python core rebuild for large state/status helpers.

This spec is the divergence ledger for the R1 port. The implementation plan is `docs/superpowers/plans/2026-07-02-rebuild-r1-core-detail.md`.

## 12. Known parity divergences

Every deliberate old-vs-new behavior change must be added here in the same commit as the code change, with a matching code comment and parity harness whitelist/expectation.

| Area | Bash behavior | Python behavior | Rationale |
|---|---|---|---|
| `improvements-status` mutating explicit invalid `--root` | `resolve_root` printed the invalid explicit root when `cd "$root"` failed, so `mark-done`/`reopen` proceeded and usually failed later as "queue file not found" under that synthetic path. | Mutating commands fail closed during root resolution (`improvements-status: cannot resolve root: <path>`, exit 2). `list` keeps observational root behavior. | R1 root canonicalization: mutating state writes must not proceed from a known-invalid explicit root. Hook-safe/read-only behavior is preserved separately. |
