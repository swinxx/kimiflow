# memory-router Python CLI - Plan 15: `provider_sync_status_json` + `vault_status_json`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the provider SYNC + vault views: `provider_sync_status_json` (Bash 1325-1351) with `provider_sync_candidates_json` (1309-1323) and `provider_sync_base_candidates_json` (1294-1307); and `vault_status_json` (1353-1397). These complete the provider/vault subsystem consumed by `status_json`. The evidence subsystem they depend on (`evidence_fingerprints_json` etc.) is already ported in `rows.py`; `provider_status_json` is Plan 14.

**Architecture:** Extend `hooks/memory_router/provider.py` with `_sync_base_candidates`, `_sync_candidates`, `sync_status_json`, `vault_status_json`. They reuse `rows.evidence_fingerprints_json`, `provider.status_json`, `store`, and `contracts.dumps` (for the fingerprint-equality compare). Returns Python dicts. No subcommand wiring.

**Tech Stack:** Python 3.9+ stdlib only; no new deps.

## Global Constraints

- **Drop-in / scope:** `provider.py` (extend, + `contracts`/`rows` imports), `tests/test_provider.py` (extend). No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash provider_sync_* (1294-1351) + vault_status_json (1353-1397) @ `kimiflow--v0.1.50`. Grounded byte-for-byte (full provider+evidence+sync/vault chain extracted, isolated `env -i`) across ~9 scenarios - see Self-Review.
- **`_sync_base_candidates` filter (exact order):** `status//current==current`; `sensitivity//normal` not in `{security,private}`; `evidence//[]` length>0; NOT `any(== "NOT VERIFIED" or == "OUTSIDE_REPO")`; `evidence_fingerprints//[]` length>0; ALL fingerprints `.status=="current"`; `id//"" != ""` AND `id` not in `manifest.synced_learning_ids`.
- **`_sync_candidates` freshness:** a base candidate is kept iff its STORED `evidence_fingerprints` equals a fresh recompute `rows.evidence_fingerprints_json(root, evidence)`. Bash compares the two `jq -c` strings; the port uses `contracts.dumps(stored) == contracts.dumps(current)` (the order-preserving compact equivalent; the stored fingerprints were written by the same tool, so key order matches).
- **`sync_status_json`:** `available = provider.available is True`; `pending_count`/`pending_ids` gated on `available` (else `0`/`[]`); `exportable_count` = candidate count regardless of available; `health_status`/`auth_status` via `//"unknown"`; `direct_write_ready = provider.health.direct_write_ready is True`; `status` ladder (`provider_detected_unconfigured` if `!available && detection.available`; elif `!available` -> `provider_unavailable`; elif count>0 -> `pending`; else `current`).
- **`vault_status_json`:** env `KIMIFLOW_VAULT_AVAILABLE` truthy -> available; a passed provider manifest sets available + `last_prefetch_at`/`last_write_at`; `MEMORY-INDEX.json` (when present AND valid+truthy JSON) sets `vault.available` and fills `last_recall`/`last_write` ONLY when still null (provider wins). Key order `{available,last_recall_at,last_write_at,provider}`.
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/provider.py` | add `contracts`/`rows` imports + `_sync_base_candidates`, `_sync_candidates`, `sync_status_json`, `vault_status_json`. |
| `hooks/memory_router/tests/test_provider.py` | add `_RootCase`, `SyncStatusCase`, `VaultStatusCase`. |

---

### Task 1: provider sync + vault

**Step 1 (Red -> Green):** Implement the four functions + tests exactly as shipped.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (263 with this plan).
- Grounding: extend the provider harness with the evidence chain + sync/vault; drive both bash and Python under isolated `env -i` over fixture roots (fresh/stale/synced/private/no-evidence/NOT-VERIFIED/archived rows; vault provider/index/env permutations); diff -> identical.
- ASCII check on `provider.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (full provider + evidence + sync/vault chain, isolated `env -i`) across ~9 scenarios: sync `pending` (one fresh candidate L1; L6 synced, L7 stale-fingerprint, Lpriv private, Lnoev no-evidence, Lnv NOT-VERIFIED, Larch archived all excluded -> `pending_ids:["L1"]`); sync `current` (all synced); sync `provider_unavailable` (dead-port detection; `exportable_count` still counts); sync `provider_detected_unconfigured` (mock detected, unconfigured); vault provider+index merge / index-only / provider-only / env-available. All identical. The fresh-fingerprint fixture was computed via the (already-ported) `rows.evidence_fingerprints_json`, so a fresh classification by BOTH bash and python also cross-checks that helper. Non-list `evidence`/`evidence_fingerprints` and non-dict fingerprints are guarded (treated as excluded) - unreachable, the recorder always writes lists of fingerprint objects.
