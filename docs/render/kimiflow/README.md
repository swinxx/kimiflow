# Kimiflow Skill Render Sources

`docs/render/kimiflow/` is the edit source for the committed host skill files:

- `canonical/SKILL.md` renders to repository-root `SKILL.md`.
- `overlays/codex.md` renders to `skills/kimiflow/SKILL.md`.

The canonical workflow in `canonical/SKILL.md` is intentionally a thin always-loaded driver. Phase detail
lives in `../../../phases/*.md`, and expanded optional scaling rules live in
`../../kimiflow-scaling-knobs.md`. Host overlays contain host-specific invocation, path, and tool
substitutions; they must point back to the canonical workflow instead of forking it.

Render after source edits:

```bash
PYTHONPATH="$PWD/hooks" python3 -m kimiflow_core.render
```

`hooks/release-consistency-check.sh` checks these rendered files and fails when the committed outputs drift.
