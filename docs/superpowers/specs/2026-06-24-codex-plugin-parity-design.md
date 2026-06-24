# Kimiflow Codex Plugin Parity Design

Date: 2026-06-24

## Goal

Kimiflow should work in Codex with the same user-facing behavior and gate guarantees it has in Claude Code. The Codex port is not a lighter documentation-only packaging pass. It must preserve the disciplined feature/fix loop, persistent `.kimiflow/<slug>/` state, mechanical shell gates, hook-backed safety checks, and opt-in invocation semantics.

## Success Criteria

- Codex can discover and install Kimiflow as a plugin through a `.codex-plugin/plugin.json` manifest.
- Codex can invoke Kimiflow as a skill with Codex-native phrasing, using `$kimiflow` or explicit plugin/skill invocation.
- The Codex skill runs the same phases and modes as the Claude Code skill: feature, `--fix`, `--audit`, `--explore`, `--prepare`, `--resume`, verbosity settings, plan-gate, implementation, verification, code-review, and commit-gate.
- The same on-disk run contract remains authoritative: `.kimiflow/<slug>/STATE.md`, phase artifacts, findings, advisories, and project memory files.
- Mechanical gates remain script-backed and fail-closed where they are fail-closed today.
- Codex lifecycle hooks provide equivalent safety coverage for commit-secret-gate, state-gate, and test-gate.
- CI validates both Claude Code and Codex packaging, hook manifests, and smoke checks.
- README and compatibility docs explain how to install and verify Kimiflow in both runtimes.

## Non-Goals

- Do not remove or weaken the existing Claude Code plugin.
- Do not split Kimiflow into a separate repository for Codex.
- Do not replace mechanical resolver scripts with prompt-only instructions.
- Do not add paid APIs or external hosted services as a requirement.
- Do not claim absolute parity for undocumented host behavior without a smoke test or a documented manual verification step.

## Architecture

Keep one repository with two host-specific packaging layers and one shared engine.

The existing Claude Code layer remains:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- root `SKILL.md`
- `hooks/hooks.json`
- shared shell scripts under `hooks/`

Add the Codex layer:

- `.codex-plugin/plugin.json`
- `skills/kimiflow/SKILL.md`
- `skills/kimiflow/agents/openai.yaml` for Codex skill metadata and explicit opt-in policy
- root `hooks.json` for Codex lifecycle hooks
- `hooks/kimiflow-root.sh` as the shared root-resolution helper for hook scripts and smoke tests
- Codex smoke tests under `hooks/`

The shell scripts remain the shared mechanical source of truth. Host-specific parsing branches are allowed only where event JSON differs.

## Codex Skill Contract

The Codex skill should be a host-native adaptation of the current `SKILL.md`, not a second workflow.

Changes required for Codex:

- Replace Claude slash-command language with Codex invocation language: `$kimiflow`, `@kimiflow`, or explicit prompt text such as "run Kimiflow".
- Keep opt-in behavior in the skill description. Codex should not auto-trigger Kimiflow for ordinary feature, bug, or refactor requests.
- Replace Claude-specific tool names with Codex equivalents or host-neutral wording.
- Replace `TaskCreate` / `TaskUpdate` with Codex plan/status guidance.
- Replace `${CLAUDE_PLUGIN_ROOT:-$CLAUDE_SKILL_DIR}` with a portable Kimiflow root-resolution rule.
- Use Codex subagent terminology: built-in `explorer`, `worker`, and `default`; custom agents are optional follow-up work, not required for parity.
- Treat web research as Codex web/search/tool availability rather than Claude `WebSearch` / `WebFetch` names.

The Codex skill must still instruct the orchestrator to read `reference.md` and to invoke the shared scripts rather than reimplementing gate logic.

## Root Resolution

Kimiflow scripts are currently referenced through Claude-specific environment variables. Codex plugin hooks commonly run relative commands such as `./scripts/...`, while skill instructions should be robust when installed in a plugin cache.

Add `hooks/kimiflow-root.sh` and source it from scripts that need the plugin root. The helper resolves paths in this order:

1. If `KIMIFLOW_PLUGIN_ROOT` is set, use it.
2. Else if `CLAUDE_PLUGIN_ROOT` is set, use it.
3. Else if `CLAUDE_SKILL_DIR` is set, use its parent when appropriate.
4. Else resolve from the script's own location: `$(cd "$(dirname "$0")/.." && pwd)`.
5. If resolution fails, print a clear error and fail closed for gate-critical scripts.

This keeps Claude compatibility while giving Codex a reliable fallback.

## Hook Parity

Codex supports plugin-bundled lifecycle hooks, but hook trust and event payloads differ from Claude Code. Kimiflow adds a root `hooks.json` for Codex and leaves `hooks/hooks.json` as the Claude Code manifest.

Codex hooks should cover:

- `PreToolUse` with matcher `Bash`: run commit-secret-gate and state-gate.
- `Stop`: run test-gate.

The Codex hook commands are relative to the plugin root:

```json
{
  "type": "command",
  "command": "./hooks/commit-secret-gate.sh",
  "statusMessage": "Checking Kimiflow commit hygiene"
}
```

Each hook script should accept both current Claude payload shapes and known Codex payload shapes. Existing parsing already handles `.tool_input.command` and `.cwd`; tests should add Codex-shaped examples and retain the current Claude tests.

Hook trust remains a host responsibility. Documentation should say Codex may ask the user to review and trust plugin hooks before they run.

The Claude Code hook manifest keeps using `CLAUDE_PLUGIN_ROOT` unless testing proves relative commands are safe there. Codex and Claude hook manifests may call the same scripts through different command strings, but they must not fork gate behavior.

## Mechanical Gates

The following scripts remain shared:

- `hooks/resolve-review-gate.sh`
- `hooks/resolve-build-gate.sh`
- `hooks/resolve-verbosity.sh`
- `hooks/commit-secret-gate.sh`
- `hooks/state-gate.sh`
- `hooks/test-gate.sh`
- `hooks/test-weakening-scan.sh`
- `hooks/secret-content-scan.sh`

Behavior should stay unchanged unless the change is required for host portability.

The review gate remains the source of truth for plan-gate and code-review gate. The orchestrator may summarize a verdict, but it cannot self-report the gate open without the resolver returning `OPEN`.

## Documentation

Update user-facing docs to describe both runtimes.

README should include:

- Claude Code install path, unchanged.
- Codex install path through a local or repo marketplace.
- Codex invocation examples using `$kimiflow` or explicit "run Kimiflow".
- A parity statement explaining that the same loop and mechanical gates are intended in both hosts.
- A short note that Codex may require hook trust review.

Compatibility docs should add a Codex section listing load-bearing Codex primitives:

- `.codex-plugin/plugin.json`
- Codex skills frontmatter and progressive disclosure
- Codex plugin marketplace entry
- Codex plugin lifecycle hooks
- Codex hook trust review
- Codex event JSON for `PreToolUse` and `Stop`
- Codex subagent model and explicit subagent spawning
- Codex MCP and web-search availability

## Tests And Validation

Automated checks:

- `jq -e` for `.codex-plugin/plugin.json`.
- `jq -e` for the Codex hook manifest.
- Existing shell syntax and unit tests stay green.
- Codex smoke test validates:
  - Codex plugin manifest exists and has required fields.
  - Codex manifest version matches the Claude manifest version.
  - Codex skill exists and has `name: kimiflow`.
  - Codex skill description includes the opt-in guard.
  - Codex hook manifest references executable scripts.
  - Synthetic Codex hook payloads trigger expected allow/block behavior for commit-secret-gate and test-gate.

Manual checks:

- Install or enable Kimiflow in Codex from the configured marketplace.
- Start a new Codex thread and invoke `$kimiflow`.
- Confirm Kimiflow appears only when explicitly requested.
- In a repo with `.kimiflow/`, confirm `git add .` is blocked.
- Confirm `.kimiflow/test-gate` blocks finishing when tests are red.
- Run a trivial Kimiflow flow through commit-gate.

## Risks

- Codex hook payloads may evolve. The scripts should parse tolerant known fields and fail safe for gate-critical paths.
- Codex plugin installation commands differ across CLI/app versions. The smoke test should validate structure automatically and document manual installation when CLI install is not available.
- Exact slash-command parity is not guaranteed because Codex skills are invoked differently. The parity target is behavioral, not identical command syntax.
- Subagent orchestration differs by host. The Codex skill should describe the desired delegation behavior in Codex-native terms and keep the same independence requirements.

## Implementation Sequence

1. Add Codex plugin manifest and skill structure.
2. Add Codex hook manifest and adapt hook path/root handling.
3. Add Codex smoke tests and CI wiring.
4. Update README and compatibility documentation.
5. Run all shell/unit/smoke checks.
6. Manually verify Codex plugin installation/invocation where the local CLI supports it.

## Acceptance Criteria

- `bash hooks/smoke-install.sh` passes for existing Claude Code structure.
- New Codex smoke test passes.
- CI validates both plugin manifests and both hook manifests.
- The Codex skill can be loaded by Codex as `kimiflow`.
- Hook scripts pass existing tests plus Codex-shaped payload tests.
- Documentation gives a working path for Claude Code and Codex users.
