```
██╗  ██╗██╗███╗   ███╗██╗███████╗██╗      ██████╗ ██╗    ██╗
██║ ██╔╝██║████╗ ████║██║██╔════╝██║     ██╔═══██╗██║    ██║
█████╔╝ ██║██╔████╔██║██║█████╗  ██║     ██║   ██║██║ █╗ ██║
██╔═██╗ ██║██║╚██╔╝██║██║██╔══╝  ██║     ██║   ██║██║███╗██║
██║  ██╗██║██║ ╚═╝ ██║██║██║     ███████╗╚██████╔╝╚███╔███╔╝
╚═╝  ╚═╝╚═╝╚═╝     ╚═╝╚═╝╚═╝     ╚══════╝ ╚═════╝  ╚══╝╚══╝ 
```

# kimiflow — Feature & Fix Loop (Claude Code skill + plugin)

A **user-invoked** Claude Code skill+plugin that runs a disciplined **8-phase loop** for **building features** and **fixing bugs**: clarify → understand/diagnose → plan → plan-gate → implement → verify → code-review → commit. Every gate is **binary and mechanical** — reviewers write structured findings to files and the gate counts the open blockers itself (and **fails closed**), so "done" is enforced, not self-reported. In **fix mode** it reproduces the bug and **proves the root cause before touching code**. It ships safety hooks (a secret-commit gate + a drive-by-safe test-gate), is **scope-gated** so small tasks stay lean, and **replies in the language you write in**.

> `SKILL.md` / `reference.md` are written in English. **kimiflow replies in the language you write in** — write in German and it grills/answers in German.

## Install

**Prerequisite:** [`jq`](https://jqlang.github.io/jq/) on your `PATH` — the hooks need it. `brew install jq` (macOS) · `sudo apt-get install jq` (Debian/Ubuntu).

**Optional (recommended):** an Obsidian (or compatible notes) MCP for the **vault memory layer** — kimiflow searches the vault before researching and saves reusable findings back, auto-discovering your vault's own structure. No vault MCP → kimiflow skips it and uses the repo-local `.flow/` memory.

### Recommended — plugin (skill **+** hooks)

Inside Claude Code:
```
/plugin marketplace add swinxx/kimiflow
/plugin install kimiflow@kimiflow
```
…or from a terminal:
```bash
claude plugin marketplace add swinxx/kimiflow
claude plugin install kimiflow@kimiflow
```
Then **restart Claude Code** (or open a new session) and run `/kimiflow`. This installs the skill **and** the safety hooks (`commit-secret-gate`, `test-gate`). Update later with `claude plugin update kimiflow`.

### Alternative — skill only (no hooks)

```bash
git clone https://github.com/swinxx/kimiflow ~/.claude/skills/kimiflow
```
Gives you `/kimiflow` (auto-discovered, no restart needed) — but **not** the hooks (`hooks.json` loads only via the plugin).

> **Public repo** — anyone can install; no access request needed. The skill fires **manually only** (`disable-model-invocation: true`) — invoke it with `/kimiflow`.

## Usage

```
/kimiflow <feature>          # build a feature
/kimiflow <bug>              # fix a bug (auto-detected)
/kimiflow --fix <bug>        # force fix mode
/kimiflow <…> --prepare      # prepare only (through plan-gate), implement later
/kimiflow --resume <slug>    # continue a prepared/interrupted run in a fresh session
```

## Example

**Feature:**
```
/kimiflow Add a dark-mode toggle in settings
```
1. kimiflow asks 2–3 plain questions (e.g. "Apply immediately or after restart?") → `INTENT.md`, asks **"Does this match?"**
2. understands the affected code (settings, theme) with `file:line` evidence, researches gaps → `RESEARCH.md`
3. plan + acceptance criteria → plan-gate → build → verify → code-review
4. shows the diff and **waits for your OK before committing**

**Bug fix:**
```
/kimiflow --fix App crashes when opening an empty project
```
1. clarifies the problem (symptom, reproduction) → `PROBLEM.md`
2. **reproduces the crash**, **proves the cause** (`file:line`), **researches the correct fix** → `DIAGNOSIS.md`. Without a proven cause it does **not** fix.
3. fixes → verifies the crash is gone + no regression → code-review → **stops before committing**

## Flow (8 phases)

Scope-gate (`trivial`/`small`/`large`) → **clarify** (plain-language grill / problem clarification) → **understand & research** resp. **diagnose** (reproduce + prove root cause + research the correct fix *before* fixing) → **plan** with testable EARS acceptance criteria → **plan-gate** (2 independent reviewers, binary no-blocker, cap 3) → **implement** (TDD, sequential by default) → **verify** against the criteria (with evidence) → **code-review** → **commit** (stops for your OK).

State is persisted to `.flow/<slug>/` in the target project (resumable).

> **Cost:** a `large` run fans out several subagents (reviewers, implementer, verifier, and optional best-of-N / cross-family reviewer) — expect noticeably higher token use. The scope-gate keeps `small`/`trivial` lean (no loop, 0–1 reviewers).

## Principles

- **Simplicity-first** — complexity scales with the work (scope-gate).
- **Binary no-blocker gates**, never a numeric score.
- **Evidence-before-assertion** — verify against specs, not vibes.
- **Fix mode:** prove the root cause and research the correct fix *before* fixing (the model may not be up to date).
- **Colored phase markers** — each of the 8 phases announces with its own color (⚪🔵🟣⚫🟡🟠🟤🟢) so a run reads at a glance in Claude Code.

Details in [`reference.md`](reference.md).

## Hooks (bundled)

kimiflow ships two safety hooks under `hooks/`, **active only in kimiflow repos** (a `.flow/` dir at the git root) so they never touch unrelated projects:

- **`commit-secret-gate`** — blocks a `git commit` that would stage a secret (`.env*`, `*.pem/.key`, `id_rsa`, `.npmrc`, `secret`/`token`/`credential` paths) and any bulk `git add -A`/`.`.
- **`test-gate`** (opt-in) — blocks finishing while the project's tests are red; enable per project via a **local, untracked** `.flow/test-gate` file (auto-enabled for `large`-scope runs). A git-tracked (committed) marker is refused — its first line is `eval`'d, so committed markers can't run as a drive-by.

---

# kimiflow — Feature- & Fix-Loop (Deutsch)

Ein **user-invoked** Claude-Code-Skill+Plugin, das einen disziplinierten **8-Phasen-Loop** fürs **Bauen von Features** und **Fixen von Bugs** fährt: Klärung → Verstehen/Diagnose → Plan → Plan-Gate → Umsetzung → Verifikation → Code-Review → Commit. Jedes Gate ist **binär und mechanisch** — Reviewer schreiben strukturierte Findings in Dateien, das Gate zählt die offenen Blocker selbst (und **failt closed**), „fertig" wird also erzwungen, nicht selbst behauptet. Im **Fix-Modus** reproduziert es den Bug und **belegt die Root-Cause, bevor Code angefasst wird**. Es bringt Sicherheits-Hooks mit (Secret-Commit-Gate + Drive-by-sicheres Test-Gate), ist **scope-gated** (kleine Tasks bleiben schlank) und **antwortet in deiner Sprache**.

> `SKILL.md` / `reference.md` sind auf Englisch geschrieben. **kimiflow antwortet in deiner Sprache** — schreibst du Deutsch, grillt/antwortet es auf Deutsch.

## Installation

**Voraussetzung:** [`jq`](https://jqlang.github.io/jq/) im `PATH` — die Hooks brauchen es. `brew install jq` (macOS) · `sudo apt-get install jq` (Debian/Ubuntu).

**Optional (empfohlen):** ein Obsidian- (oder kompatibler Notes-) MCP für die **Vault-Memory-Schicht** — kimiflow durchsucht den Vault vor dem Recherchieren und speichert wiederverwendbare Erkenntnisse zurück, wobei es die Struktur deines Vaults selbst erkennt. Kein Vault-MCP → kimiflow überspringt ihn und nutzt die repo-lokale `.flow/`-Memory.

### Empfohlen — Plugin (Skill **+** Hooks)

In Claude Code:
```
/plugin marketplace add swinxx/kimiflow
/plugin install kimiflow@kimiflow
```
…oder im Terminal:
```bash
claude plugin marketplace add swinxx/kimiflow
claude plugin install kimiflow@kimiflow
```
Dann **Claude Code neu starten** (oder neue Session) und `/kimiflow` aufrufen. Das installiert den Skill **und** die Sicherheits-Hooks (`commit-secret-gate`, `test-gate`). Später aktualisieren mit `claude plugin update kimiflow`.

### Alternative — nur Skill (ohne Hooks)

```bash
git clone https://github.com/swinxx/kimiflow ~/.claude/skills/kimiflow
```
Gibt dir `/kimiflow` (automatisch erkannt, kein Neustart nötig) — aber **nicht** die Hooks (`hooks.json` lädt nur über das Plugin).

> **Öffentliches Repo** — jeder kann installieren; kein Zugriffsantrag nötig. Der Skill springt **nur manuell** an (`disable-model-invocation: true`) — Aufruf mit `/kimiflow`.

## Nutzung

```
/kimiflow <feature>          # Feature bauen
/kimiflow <bug>              # Bug fixen (wird automatisch erkannt)
/kimiflow --fix <bug>        # Fix-Modus erzwingen
/kimiflow <…> --prepare      # nur vorbereiten (bis Plan-Gate), später umsetzen
/kimiflow --resume <slug>    # vorbereiteten/abgebrochenen Lauf in neuer Session fortsetzen
```

## Beispiel

**Feature:**
```
/kimiflow Dunkelmodus-Schalter in den Einstellungen
```
1. kimiflow stellt 2–3 einfache Fragen (z. B. „Sofort wirksam oder erst nach Neustart?") → `INTENT.md`, fragt **„Passt das so?"**
2. versteht den betroffenen Code (Settings, Theme) mit `file:line`-Beleg, recherchiert Lücken → `RESEARCH.md`
3. Plan + Akzeptanzkriterien → Plan-Gate → baut → verifiziert → Code-Review
4. zeigt den Diff und **wartet auf dein OK vor dem Commit**

**Bug-Fix:**
```
/kimiflow --fix App stürzt ab beim Öffnen eines leeren Projekts
```
1. klärt das Problem (Symptom, Reproduktion) → `PROBLEM.md`
2. **reproduziert den Crash**, **belegt die Ursache** (`file:line`), **recherchiert den korrekten Fix** → `DIAGNOSIS.md`. Ohne belegte Ursache wird **nicht** gefixt.
3. fixt → verifiziert, dass der Crash weg ist + keine Regression → Code-Review → **Stopp vor dem Commit**

## Ablauf (8 Phasen)

Scope-Gate (`trivial`/`small`/`large`) → **Klärung** (Grill in einfacher Sprache / Problem-Klärung) → **Verstehen & Recherche** bzw. **Diagnose** (reproduzieren + Root-Cause belegen + korrekten Fix recherchieren *vor* dem Fix) → **Plan** mit testbaren EARS-Akzeptanzkriterien → **Plan-Gate** (2 unabhängige Reviewer, binär kein-Blocker, Cap 3) → **Umsetzung** (TDD, default sequenziell) → **Verifikation** gegen die Kriterien (mit Evidenz) → **Code-Review** → **Commit** (stoppt für dein OK).

State wird nach `.flow/<slug>/` im Zielprojekt persistiert (resume-fähig).

> **Kosten:** ein `large`-Run fächert mehrere Subagents auf (Reviewer, Implementer, Verifier, optional Best-of-N / Cross-Family-Reviewer) — entsprechend höherer Token-Verbrauch. Das Scope-Gate hält `small`/`trivial` schlank (kein Loop, 0–1 Reviewer).

## Prinzipien

- **Simplicity-first** — Komplexität skaliert mit der Arbeit (Scope-Gate).
- **Binäre Kein-Blocker-Gates**, nie ein numerischer Score.
- **Evidence-before-assertion** — gegen Specs verifizieren, nicht gegen Bauchgefühl.
- **Fix-Modus:** Root-Cause belegen und den korrekten Fix recherchieren *bevor* gefixt wird (das Modell ist evtl. nicht am aktuellen Stand).
- **Farbige Phasen-Marker** — jede der 8 Phasen meldet sich mit eigener Farbe (⚪🔵🟣⚫🟡🟠🟤🟢), damit ein Lauf in Claude Code auf einen Blick lesbar ist.

Details in [`reference.md`](reference.md).

## Hooks (mitgeliefert)

kimiflow bringt zwei Sicherheits-Hooks unter `hooks/` mit, **nur in kimiflow-Repos aktiv** (ein `.flow/`-Verzeichnis am Git-Root) — also nie in fremden Projekten:

- **`commit-secret-gate`** — blockt einen `git commit`, der ein Secret stagen würde (`.env*`, `*.pem/.key`, `id_rsa`, `.npmrc`, `secret`/`token`/`credential`-Pfade), sowie jedes Bulk-`git add -A`/`.`.
- **`test-gate`** (opt-in) — blockt das Beenden, solange die Projekt-Tests rot sind; pro Projekt via **lokaler, untracked** `.flow/test-gate`-Datei aktivieren (für `large`-Läufe automatisch). Ein git-getrackter (committeter) Marker wird abgelehnt — seine erste Zeile wird `eval`'t, committete Marker können so nicht als Drive-by laufen.
