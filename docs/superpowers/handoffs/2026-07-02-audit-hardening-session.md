# Handoff — Audit-Hardening-Programm: Baseline-Audit done, Batch 1+2 gefixt, Batch 3–5 offen

**Date:** 2026-07-02 · **Repo:** kimiflow · **Branch:** `main` · **HEAD:** `0db55a2` (working tree clean, NICHT gepusht/released)

---

## Auftrag (User-Ziel, wörtlich sinngemäß)

Das Repo so umbauen, dass es "in jedem Audit 10/10 bekommt — das beste System der Welt, ausgeklügelt, token-effizient, durchdacht, so optimiert, dass Opus 4.8 + ChatGPT an Fable-5-Ergebnisse herankommen".

**Operative Übersetzung (mit User kommuniziert, akzeptiert):** LLM-Scores sind nicht kalibriert (sagt kimiflows eigene Doku). Das erreichbare Ziel ist: **null offene BLOCKER/HIGH über unabhängige, adversariale Multi-Lens-Audits** + Beseitigung der strukturellen Schwächen (v. a. Instruction-Last/Token-Ökonomie).

**Programm:** Baseline-Audit (7 Lenses) → B1 Prosa-Kohärenz → B2 Hook-Fixes → B3 Python-Fixes → B4 Token-Restrukturierung → B5 Re-Audit. B1+B2 sind fertig; B3–B5 offen.

**Prozessregeln des Users (global CLAUDE.md, bindend):** Plan-Audit durch externe Auditor-Agents vor jeder nicht-trivialen Implementierung (binär, BLOCKER/HIGH fixen, Cap ~3 Runden); TDD (failing test first) für jeden Bug-Fix; keine AI-Attribution in Commits; nur benannte Pfade stagen; Anti-Halluzination (falsches Finding schlimmer als fehlendes).

---

## Was in dieser Session passiert ist

### Vorarbeit (bereits released als 0.1.54/0.1.55, Kontext)
- **0.1.54** (`8324fef`): "Agentic quality upgrade" — Cross-Family-Review als Default (eine Lens pro Gate via `codex exec --output-last-message` / `claude -p`), per-role Model-Routing (reference.md "Model routing (per-role)"), Dual-Plan-Selektion bei `large`, Best-of-2-Auto-Offer, additiver Verifier, Refutation-Pflicht für BLOCKER/HIGH-Kandidaten, `.kimiflow/cross-family` `auto|off`. Ging durch 3 Plan-Audit-Runden.
- **0.1.55** (`2f5048d`): Calm launcher status UX (User/andere Session).

### Baseline-Audit: 7 unabhängige adversariale Auditoren (alle fertig)
Lenses: Token-Ökonomie · Flow-Kohärenz · Instruktions-Konsistenz · memory_router-Python · Hooks-Codequalität · Bash-Gate-Verhalten · Hook-Security. Alle Findings unten sind vom Orchestrator gegen den Code verifiziert bzw. von den Auditoren mit Repro-Kommandos belegt.

### Commit `2b5c096` — B1: Prosa-Kohärenz-Fixes (SKILL.md, reference.md)
- `full`-Alias erzwingt den Pre-Build-Approval-Stopp jetzt AUCH bei `build-gate off` (war widersprüchlich).
- Phase 7 Schritt 4 staged die benannten Pfade VOR den Advisory-Scans (lasen vorher einen leeren staged diff).
- Resume in Phase 5 läuft durchs Working-Tree-Gate; Gate hat eigene `##`-Sektion in reference.md.
- Phase-5-Red-Test-Commit = definierte einzige Ausnahme der Commit-Gate-Regel (beide Dateien).
- Best-of-2-Kandidaten-Failure: degradiert zu best-of-1 (Implementer-Seat substituiert NIE same-family).
- Audit-Mode-Reviewer sehen `AUDIT-INTENT.md` + `AUDIT.md`.
- `quick` = review light definiert (EINE Lens `bug-regression` + Advisories) — in Alias + Phase 7.
- Phantom "split promoted files" entfernt; "Current-State Pulse / Gate"-Pointer angeglichen.

### Commit `0db55a2` — B2: Hook-Fixes (alle test-first, alle reproduziert)
- **hooks/hooks.json + hooks.json (Codex): unquoted `${KIMIFLOW_PLUGIN_ROOT:-…}`** → bei Pfad mit Leerzeichen (dieses Repo!) exit 126/127 → PreToolUse-Gates still **fail-open**. Gequotet; neuer `hooks/test-hooks-json.sh` fährt jeden Hook-Befehl aus einem spaced root.
- **active-run.sh**: `prompt-context`/`stop-gate` exit(2) ohne jq → blockierte JEDEN Prompt in JEDEM Repo. Degradieren jetzt zu exit 0; CLI-Subcommands behalten need_jq. Tests ergänzt.
- **plan-blocker-gate.sh**: Audit-Mode-DEADLOCK (PLAN/ACCEPTANCE hart verlangt, Audit erzeugt sie nie). Audit-Profil eingebaut (Mode aus STATE.md via `state_value`, Fallback AUDIT-INTENT∧¬PLAN; verlangt AUDIT.md-Pfad-Evidenz + affected paths + Clarify-Recheck). 4 neue Tests; SKILL.md Phase-4-Step-0 erwähnt das Profil.
- **resolve-review-gate.sh**: Anti-Oszillation/Reappeared globten `r<N>-*.md` über ALLE Lenses → Phase-4-Reste maskierten echte Phase-7-Oszillation (Pflicht-Stop unterdrückt). Prev-Runden-Checks jetzt `--expect`-scoped (`expected_round_files`/`id_in_round`); `round`/`cap` base-10-normalisiert (Octal-Crash `08`). Cross-Phase-Isolationstest ergänzt.
- **commit-secret-gate.sh**: `git add ./`, `git add :/`, `:(top)` (Whole-Tree) umgingen die Bulk-Sperre. Regex erweitert (+`-A`-Cluster, Quote-Strip im Bulk-Check — safe, liest nur Flags). 6 neue Testfälle.
- **CI (.github/workflows/ci.yml)**: 19 hartcodierte Teststeps → Discovery-Loop über ALLE `hooks/test-*.sh` (exkl. Produktions-Hooks `test-gate.sh`, `test-weakening-scan.sh`); `shellcheck --severity=error` ist Hard-Gate (error-clean verifiziert), warning-Level informational.

**Verifiziert:** alle 31 Test-Suiten grün, ShellCheck error-clean, release-consistency grün, CI-Loop lokal simuliert.

---

## OFFEN — Batch 3: memory_router-Python-Fixes (3 MEDIUMs, vom Auditor reproduziert)

TDD: failing test first. Suite: `bash hooks/test-memory-router-unit.sh` (491 Tests). ACHTUNG Parity: `hooks/test-memory-router-parity.sh` difft gegen den gepinnten Bash-Tag `kimiflow--v0.1.50` — prüfen, ob die Fixes Parity-Cases brechen (bewusste Divergenz dann im Parity-Harness als dokumentierte Ausnahme behandeln, Muster existiert dort).

- **P1 `hooks/memory_router/rows.py:76` (+:110):** `sanitize_evidence_ref` macht rohes `startswith(root+"/")` ohne Normalisierung → `../../etc/hosts` gilt als in-repo, `evidence_fingerprints_json` hasht Out-of-repo-Dateien. Fix: `os.path.normpath`/`realpath` vor dem Root-Check. Repro: `python3 -c "import sys;sys.path.insert(0,'hooks');from memory_router import rows;print(rows.evidence_fingerprints_json('/tmp/a/b/c',['../../../../etc/hosts']))"`.
- **P2 `hooks/memory_router/writes.py:112` (+store.py:61):** Full-Rewrite-Pfad (record mit status=current bei existierender LEARNINGS.jsonl) re-serialisiert nur lenient geparste Rows → Nicht-JSON-Zeilen werden still verworfen (Append-Pfad erhält sie — inkonsistent). Fix: unparsebare Zeilen beim Rewrite verbatim erhalten.
- **P3 `hooks/memory_router/writes.py:51`:** Security-Gate scannt nur `summary` (Phrasen, keine Secret-VALUES); Secrets in topic/evidence oder nackte Key-Werte werden sensitivity=normal → landen im VAULT-SYNC-Kandidatenset. Fix: topic+evidence mitscannen + minimale Secret-Value-Patternklasse (AWS/API-Key-Formen) → erzwinge sensitivity=security (blockt Sync-Kandidatur).

## OFFEN — Batch 4: Token-Restrukturierung (der große Hebel, User-Kernziel)

Messbasis (Token-Auditor, gegen echte Dateien): SKILL.md 59,6K chars (~15K tok) always-loaded; nacktes `/kimiflow` ≈ **29K tok** vor der ersten User-Wahl; kleiner Run lädt ~36K tok Instruktions-Prosa; jeder Reviewer-Spawn bekommt die 11,5K-Rubrik statt der nötigen 1,7K-Grammatik. Ziel: SKILL.md ≤ ~30K chars, kein Regelverlust — Single-Copy-Authority + Pointer. **Vor Umsetzung dem User die Struktur zeigen (zugesagt!), dann externes Plan-Audit (Regel 8).**

- T1 HIGH `hooks/launcher-status.sh`: 43,7K chars JSON beim Launcher (`--pretty` +44%; `runs.items` 13,3K für 27 done-Runs). Fix: First-Screen = counts + primary_action (compact); Items hinter `--full`/Drilldown; SKILL.md-Launcher-Step + Tests anpassen.
- T2 HIGH: Reviewer-Delegationen inlinen die kanonische FINDING/CANDIDATE-Grammatik (~1,7K, <15-Zeilen-Verbatim-Regel SKILL.md erlaubt das) statt der ganzen Rubrik; Rubrik bleibt Orchestrator-only.
- T3 HIGH: Phase 6 nahezu wortgleich doppelt (SKILL.md ↔ reference.md "Verification") → eine Kopie.
- T4 HIGH: SKILL.md Phase-7-Learning-Loop-Zeile (4.025 chars) restated die Memory-Router-Sektion → auf Command-Sequenz + Pointer kürzen.
- T5–T13 MED/LOW: Lenses-Definitionen doppelt; Pre-Build-Gate 3×; Launcher-Gruppen-Aufzählung 3×; Aliase 2×; Commit-hygiene-Maintainer-Doku (5,7K von 6,2K) → docs/; Rare-Path-Prosa (audit/explore/verify-feature/large-Knobs ≈6K) → reference; Verbosity-Invariante 4×; Frontmatter-Description 1,2K; Clarify-Marker + Working-tree-Text dedupen. Konsolidierte Per-Phase-Pointer (kleiner Run zeigt auf 15 Sektionen ≈ 84K chars — Project-Map-Sektion 15,4K wird auch bei abgelehnter Map gelesen).
- Constraint: jede Gate-Command-/Stop-/Fail-closed-Regel behält mindestens eine always-loaded Erwähnung.

## OFFEN — Batch 5 + Restbefunde

- **Re-Audit** nach B4: frische Konsistenz- + Token-Auditoren über die restrukturierten Dateien; volle Suite + Smokes.
- Kleinere offene Findings: `state-gate.sh:61` Deny-Message behauptet "only trivial runs without STATE" (widerspricht SKILL.md; Wording angleichen) · Helper-Drift `resolve_root` (agentic-readiness `pwd -P`+hard-die vs. logical+fallback in 3 Siblings) und `state_value` case-(in)sensitivity (clarify-gate vs. active-run/launcher) · `project-map-status.sh` bare `mktemp` in $TMPDIR + `mv` (cross-device nicht atomar, 0600-Mode, ENOSPC druckt trotzdem REFRESHED; Zeilen ~314/425/441/537) · release-Skill loopt `hooks/test-*.sh` inkl. der 2 Produktions-Hooks (CI exkludiert sie jetzt; release/SKILL.md ggf. angleichen) · Codex-Port Schreibweise "Current-State Pulse/Gate" · test-gate.sh untracked-Marker-Trust-Boundary (dokumentierter Residual — Entscheidung: belassen).
- **CHANGELOG:** `## Unreleased` steht noch auf "_No unreleased changes._" — die zwei Fix-Commits (`2b5c096`, `0db55a2`) brauchen Unreleased-Einträge, bevor `/release` läuft (release-consistency verlangt den Block-Stil; Muster siehe 0.1.53/0.1.54).
- **Nicht gepusht:** beide Commits liegen nur lokal auf `main`.

---

## Arbeitsweise, die sich bewährt hat (beibehalten)

1. Findings NIE ungeprüft übernehmen: Orchestrator verifiziert am Code (die Auditoren liefern Repro-Kommandos — ausführen).
2. Jeder Hook-Fix: failing Test zuerst, im bestehenden Stil des jeweiligen `test-*.sh` (pass/fail-Helper, mktemp-Fixtures, NOJQ-PATH-Pattern für jq-lose Pfade).
3. Nach jedem Batch: alle Suiten + `release-consistency-check.sh` + gezielter Diff-Review, dann Commit mit benannten Pfaden.
4. Bash 3.2 (macOS) ist Target: keine Assoziativ-Arrays, `${arr[@]+...}`-Idiom, Vorsicht mit `set -u` + leeren Arrays.
5. User-Kommunikation: Deutsch, TLDR zuerst; bei großen Umbauten (B4!) erst Struktur zeigen, dann bauen.
