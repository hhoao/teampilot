# Team Builder skill optimization — Design

**Date:** 2026-09-01  
**Status:** Approved in brainstorming; pending written-spec review

## Context

TeamPilot's agentic “Generate and launch” workflow uses a visible temporary
Simple session as a Team Builder. The existing workflow design already defines
Team Composer MCP, durable generation jobs, profile commit, and handoff. This
amendment focuses on the builder skill and message semantics after comparing
the repository's Claude Code Agent Teams prompts:

- `packages/builtin-tools/src/tools/TeamCreateTool/prompt.ts`
- `packages/builtin-tools/src/tools/AgentTool/prompt.ts`
- `src/coordinator/coordinatorMode.ts`

The Claude prompts provide useful collaboration rules—team lifecycle, role
selection, task ownership, naming, communication, and idle behavior—but
TeamPilot must keep its app-owned Team Composer MCP and TeamBus architecture.
It must not depend on Claude Code's native `TeamCreate` runtime.

## Scope

This design updates:

1. the app-managed `team-builder` skill;
2. the generated builder kickoff message;
3. skill dependency mapping for the app-managed skill;
4. normal message-history and PTY delivery semantics for synthetic messages;
5. tests covering resource loading, message delivery, MCP workflow, and
   handoff.

It does not modify the Claude Code repository, introduce native
`TeamCreate` calls, or add a phase-status row to the TeamPilot UI.

The existing New Team dialog and its headless draft flow remain unchanged.

## Product decisions

1. Team Builder is a temporary, visible Simple session with
   `SessionPurpose.teamGeneration`.
2. The builder uses Team Composer MCP to create an app-owned team plan; it
   does not call native `TeamCreate`, `TaskCreate`, `Agent`, or
   `SendMessage` for team creation.
3. The original user request is persisted as immutable `originalPrompt` in the
   generation job.
4. Kickoff is a TeamPilot-generated synthetic user message consisting of fixed
   builder instructions plus the original request.
5. Kickoff uses the same message submission contract as an input-box message:
   history record, UI user bubble, delivery ID, PTY delivery, and retry-safe
   reconciliation.
6. Handoff delivers the unchanged `originalPrompt` as a normal user message to
   the generated team's lead.
7. Generation phases remain durable job data and diagnostics only. They are
   not rendered as additional phase-status UI.
8. Normal agent recovery is delegated to the builder. TeamPilot does not add
   fixed retry loops or preflight gates for ordinary MCP failures.

## Lifecycle and boundaries

```text
Landing request
  -> persist generation job
  -> create visible Team Builder Simple session
  -> persist and deliver synthetic kickoff
  -> Team Builder reads context and designs a plan
  -> Team Composer MCP validates and finalizes the plan
  -> TeamPilot commits profile and staged resources
  -> create the destination Team session
  -> persist and deliver originalPrompt to the lead
  -> clean up the builder after successful handoff
```

| Component | Responsibility | Boundary |
|---|---|---|
| Team Builder skill | Understand task, select roster, select resources, revise plan | Does not edit TeamPilot manifests or perform the original task |
| Catalog MCP | Search and acquire skills, plugins, and MCP resources | Does not silently mutate unrelated global bindings |
| Team Composer MCP | Provide context, probes, validation, and finalize operation | Does not expose arbitrary session/profile mutation |
| Generation coordinator | Own durable job, session creation, commit, handoff, and recovery state | Does not parse model prose or replace agent planning |
| TeamPilot message pipeline | Persist synthetic/user messages and deliver them to PTY | Does not treat direct PTY writes as history |
| TeamBus | Runtime member-to-member communication for the generated team | Is not the builder's planning protocol |

After `finalize_team_generation` is accepted, the builder must stop. It must
not implement the original request or make additional planning calls.

## Team Builder skill protocol

The managed skill at `team-builder` is rewritten using the Claude prompt's
structured workflow, adapted to TeamPilot's MCP tools.

### 1. Read context first

The builder first calls `get_generation_context` and uses the returned facts
about the task, workspace targets, launch capabilities, model pool, workflow,
and resource bindings. It must not infer unavailable workspace configuration
from the kickoff text.

### 2. Decide the smallest useful roster

- A single continuous workflow still gets a lead and one useful supporting
  role; do not create a team with only one role.
- Independent workstreams get separate specialists.
- Clear frontend/backend/test/review or research/implementation boundaries may
  produce three to five roles.
- The plan contains two to five roles, exactly one `team-lead`, and no duplicate
  responsibilities.

Every role has a stable name, purpose, inputs, outputs, boundaries, required
CLI/provider/model/effort, required resources, write capability, and
coordination relationship to the lead.

### 3. Discover and bind resources

The builder uses Catalog MCP to search, inspect, and acquire resources into
generation staging. It must not invent IDs. The app-managed `team-builder`
skill is resolved through `ManagedTeamBuilderSkillProvider`; it is not a
Superpowers catalog reference.

Staged resources are included in the plan and become durable only through the
TeamPilot commit boundary.

### 4. Validate and revise

The builder calls `validate_team_plan`, reads the returned errors, and revises
only the affected plan fields before validating again. MCP errors are returned
to the agent as ordinary tool errors. The skill tells the agent to inspect the
error and retry or correct its request; the coordinator does not wrap ordinary
MCP calls in a fixed retry loop.

`finalize_team_generation` is accepted once for a workflow. The operation is
workflow-ID scoped and idempotent so an explicit transport retry cannot create
a second team commit.

### 5. Stop after finalization

After finalization succeeds, the builder only reports a concise completion
message and stops. It never edits `profile.json`, workspace project config,
session files, or other TeamPilot control-plane files directly.

## Skill dependency mapping

The generic expert helper currently maps every skill slug to the Superpowers
repository. That turns the built-in builder dependency into the invalid ID
`obra/superpowers:team-builder`.

The mapping must distinguish:

```text
Superpowers skill       -> obra/superpowers:<slug>
TeamPilot managed skill -> team-builder
```

The fix should use a dedicated managed-skill dependency/reference for the
built-in Team Builder expert. The runtime must materialize the managed skill
only for `SessionPurpose.teamGeneration` sessions and must not expose it to
ordinary Simple or Team sessions.

## Synthetic message semantics

Kickoff is not a simulated input-widget click. It is a programmatic call to
the same application-level submission contract used by the input box.

```text
fixed builder instruction + originalPrompt
  -> append one user history record
  -> render one user bubble
  -> assign stable deliveryId
  -> deliver to builder PTY
  -> reconcile CLI transcript
```

The job stores the raw `originalPrompt` separately. The kickoff may wrap it
with builder instructions, but handoff must send the raw value unchanged to
the generated lead. The same delivery ID prevents duplicate kickoff delivery
after restart or reconnect.

## User-visible behavior

- The builder tab is visible as a normal temporary Simple session.
- The fixed kickoff appears as one user bubble.
- The builder's normal CLI output and tool transcript remain visible through
  existing terminal/history rendering.
- No additional workflow phase-status row or phase-status chat bubbles are
  introduced.
- On successful handoff, the destination Team session becomes active and the
  lead receives one user bubble containing the original request.
- If handoff fails, the builder and durable job remain available for recovery.

## Error and recovery policy

This feature does not add defensive preflight checks for every expected
runtime condition. Resources and MCP servers are wired by construction.

- Ordinary MCP call failure is an agent-recoverable tool error.
- Validation failure is an agent-recoverable plan correction.
- The coordinator records receipts and durable phase transitions; it does not
  make planning decisions or run generic retry loops.
- A process restart resumes from the last durable receipt without duplicating
  an accepted delivery or commit.
- A terminal failure in session creation or handoff remains attached to the
  generation job and does not silently fall back to an unrelated Simple
  session.

## Verification

Add or update tests for:

1. built-in Team Builder dependency resolution to `team-builder`;
2. managed skill materialization in a generation session;
3. synthetic kickoff history and PTY delivery sharing one delivery ID;
4. restart/retry reconciliation without duplicate kickoff or original prompt;
5. MCP validation errors being returned to the builder without coordinator
   retry loops;
6. accepted finalize being idempotent by workflow ID;
7. raw `originalPrompt` reaching the generated lead unchanged;
8. handoff failure preserving the builder job;
9. no new phase-status UI being emitted.

## Reference

The Claude Code comparison source is local to
`/home/hhoa/git/opensource2/claude-code`. The current Claude Code Agent Teams
documentation is also relevant for conceptual comparison:

- <https://code.claude.com/docs/en/agent-teams>
- <https://code.claude.com/docs/en/tools-reference>

TeamPilot intentionally adopts the collaboration guidance, not the native
Claude-specific team storage or tool lifecycle.
