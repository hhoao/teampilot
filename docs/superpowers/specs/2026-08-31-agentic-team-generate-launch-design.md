# Agentic team generate-and-launch — Design

**Date:** 2026-08-31
**Status:** Approved

## Problem

Landing can launch a selected team, while the existing New Team dialog can ask
`TeamConfigGenerator` to produce a JSON draft through a headless AI call. That
headless flow is a poor fit for “generate and launch”:

- the user sees a progress bar rather than the agent's reasoning, tool calls,
  dependency choices, and recoverable errors;
- generation can only return one JSON object, so it cannot inspect machines,
  search or install resources, authenticate an MCP server, or revise a rejected
  plan in conversation;
- creating the team, assigning machines, opening the destination session, and
  delivering the original task would become a large UI-owned orchestration;
- a partial failure after team creation is difficult to resume without creating
  duplicate teams, experts, placements, or sessions.

The desired experience is an agentic workflow. Landing opens a temporary,
visible Team Builder conversation. A built-in skill guides the builder agent;
session-scoped MCP tools expose the generation context, catalog acquisition,
machine probing, validation, commit, and handoff. Once the generated team is
running and the original task has reached its lead, TeamPilot removes the
temporary conversation.

## Product decisions

1. Generation settings are global across workspaces.
2. Model-pool order is strength order. A pool entry may be assigned to any
   number of members.
3. Landing generation runs in a real, visible session rather than a headless
   request or progress overlay.
4. The builder may search, acquire, and bind skills, plugins, and MCP servers to
   the generated team without a per-resource confirmation prompt. Authentication
   or credentials that inherently require the user still pause the workflow.
5. TeamPilot performs read-only probes of every workspace-backed candidate
   target before machine assignment.
6. Successful handoff permanently deletes the temporary session. A failed or
   incomplete workflow keeps it so the agent and user can correct the plan.
7. The existing New Team dialog remains unchanged and keeps using the current
   headless draft flow.

## Goals

1. Add Landing “Generate and launch” as an agentic, observable, conversational
   workflow.
2. Let the agent choose the smallest useful roster, assign global CLI presets,
   acquire team resources, and assign roster instances to workspace machines.
3. Reuse TeamPilot's CLI registry, catalog modules, profile persistence,
   placement rules, session launch pipeline, terminal delivery, and workbench
   navigation.
4. Make every mutating operation session-scoped, validated, idempotent, and
   recoverable after process restart.
5. Preserve exact launch semantics: the original Landing message becomes the
   first prompt delivered to the generated team's lead.
6. Keep CLI behavior capability-driven. Do not add scattered per-CLI branches.

## Non-goals

- Replacing the AI flow in `HomeNewTeamDialog`.
- Letting a model write `profile.json`, workspace manifests, or session files
  directly.
- Exposing a general-purpose MCP tool that can switch to or delete an arbitrary
  session.
- Installing CLIs on remote machines automatically. Target probes report
  missing CLIs; the builder must choose another target or leave a recoverable
  blocker.
- Inferring machine suitability from undisclosed hardware. The first version
  uses probe facts, folder ownership, CLI availability, and agent judgment.
  Optional target annotations can extend the context later without changing
  the plan contract.
- Making catalog installations transactional across external OAuth providers.
  The workflow can stage acquisition and resume after required user action, but
  cannot roll back an external authorization grant.

## User experience

### Landing

The Team selector menu adds `TeamLandingChipAction.generateLaunch` next to
recent teams and “Browse all”. Selecting it keeps the conversation in Team mode
but changes the automatic chip to “Generate and launch”. The gear opens global
generation settings instead of a selected team's settings.

The send button preflights only what is needed to start the builder:

- non-empty task text;
- a configured `AiFeatureId.teamGenerate`;
- a launchable generator CLI with session, skill, and MCP capabilities;
- at least one valid effective model-pool entry;
- a valid native CLI selection when generation mode is native.

Submitting creates a temporary builder session and opens it immediately. There
is no headless progress overlay. The conversation itself shows model output,
tool calls, catalog activity, machine probe progress, validation feedback, and
questions the agent asks the user.

### Builder conversation

Builder sessions have a distinct title and badge, such as “Building team ·
OAuth migration”. They remain normal workbench sessions for navigation and
history, but expose a workflow status row and a Cancel action. Navigating away
does not stop generation.

Cancel first records a terminal cancellation receipt, stops further workflow
mutations, disposes the builder runtime, removes uncommitted staging, deletes
the temporary session, and removes the pre-commit workflow directory last. If
a team was already committed, Cancel does not silently delete it; the UI
reports the committed team and offers normal team/session actions.

### Handoff

When finalization has committed a valid team and staged the target session,
TeamPilot switches the workbench to that target session. Existing launch chrome
shows provisioning and connection progress. Once the lead accepts the original
prompt, the builder session is deleted automatically and disappears from the
sidebar.

Pre-commit failures remain in the builder. A connection or delivery failure
after the destination tab opens leaves both the destination and builder
sessions available. The destination shows its normal error/retry UI, while the
builder job retains enough state for a non-duplicating retry.

## Architecture

```text
Landing
  -> TeamGenerationCoordinator.start
       -> persist TeamGenerationJob
       -> create Simple builder AppSession
       -> open builder in WorkbenchCubit
       -> deliver original task to builder
            -> built-in team-builder skill
            -> Catalog MCP (generation staging)
            -> Team Composer MCP (context/probe/validate/finalize)
                 -> GeneratedTeamCommitService
                 -> TeamGenerationHandoffService
                      -> normal SessionLaunchService
                      -> open destination workbench tab
                      -> wait for lead input readiness
                      -> deliver original task
                      -> cleanup builder after MCP response + idle
```

### Component boundaries

| Component | Responsibility | Must not do |
|---|---|---|
| `TeamGenerationCoordinator` | Start, resume, cancel, and observe a workflow | Parse model prose or mutate profile JSON |
| `TeamGenerationJobStore` | Atomically persist workflow state in a workspace workflow directory | Own cubits or UI navigation |
| `TeamGenerationSettingsStore` | Persist global generation defaults and ordered pool | Resolve live presets or targets |
| Team Builder skill | Guide the model through inspect, acquire, validate, finalize | Write TeamPilot control-plane files |
| Catalog MCP generation scope | Search/read/acquire resources and record staged IDs | Bind resources to the workspace by default |
| Team Composer MCP | Expose workflow-safe context and commands | Accept an arbitrary workspace/session identity |
| `TeamTargetProbeService` | Read-only, bounded probes of workspace-backed targets | Install CLIs or mutate remote state |
| `GeneratedTeamPlanValidator` | Pure structural and launch validation | Persist anything |
| `GeneratedTeamCommitService` | Idempotently materialize experts, profile, resources, placement | Open UI or inject PTY input |
| `TeamGenerationHandoffService` | Create/open destination session and deliver original prompt | Decide or rewrite the team plan |

These services use constructor-injected repositories and callbacks so tests do
not need real subprocesses, SSH connections, or Flutter widget state.

## Persistent models

### Global generation settings

Add `TeamGenerationSettings`:

```dart
class TeamGenerationSettings {
  final int schemaVersion;
  final TeamMode teamMode;
  final CliTool nativeCli;
  final List<GenerateModelPoolEntry> modelPool;
}

class GenerateModelPoolEntry {
  final String presetId;
  final String description;
  final List<String> tags;
}
```

Persist it at:

```text
<teampilotRoot>/ui/team-generation-settings.json
```

`AppPaths` lives in `client/lib/services/storage/app_storage.dart`; add the
static resolver and instance getter there. The store follows existing
`Filesystem`/`AppStorage.fs` patterns and uses `atomicWrite`.

Pool entries are unique by trimmed `presetId`. On load, the first occurrence
wins and later duplicates are discarded; settings saves prevent adding a
duplicate. The store preserves order and unknown preset references so the
settings UI can render them as broken rather than silently destroying user
intent. Runtime resolution joins entries against
`CliPresetsCubit.state.presets` and produces an immutable effective snapshot:

- mixed: every valid referenced preset whose CLI is team-launchable;
- native: only valid presets matching `nativeCli`, and `nativeCli` must support
  native team launch;
- rank is the one-based position after effective filtering;
- provider/model/effort are copied into the job snapshot without credentials.

The first effective preset is the generated team's default preset and is not
model-controlled. Every pool entry may be reused by multiple members.

### Landing preference

`LandingPrefs` and `LandingLaunchContext` gain `generateLaunch`, defaulting to
false on old JSON. The invariant is:

```text
generateLaunch => !isPersonal
```

Switching to Simple clears `generateLaunch`. Selecting a concrete team clears
it. Selecting “Generate and launch” sets Team mode plus `generateLaunch` while
retaining the last concrete `teamId` for a future return to ordinary Team mode.
The global team mode and native CLI do not belong in per-workspace Landing
preferences.

### Session purpose

Add a forward-compatible `SessionPurpose` string enum to `AppSession`:

```text
normal          (default for missing/unknown persisted values)
teamGeneration
```

Add optional `workflowId`. A builder receives a UUID workflow ID distinct from
the session ID. Tool authorization requires all of:

- the addressed `AppSession` exists;
- `purpose == teamGeneration`;
- its `workflowId` matches the job;
- the request presents the unguessable workflow token stored only in the
  builder runtime MCP config;
- the session and job workspace IDs match.

Purpose and workflow ID are persisted so recovery does not rely on an expert
key or display title. Unknown purpose strings decode to `normal` and never gain
workflow privileges.

### Generation job

Persist one durable `TeamGenerationJob` outside the temporary builder session,
under the owning workspace:

```text
workspace/workspaces/<workspaceId>/team-generation/<workflowId>/
  job.json
  staging/
```

This separation is required because successful cleanup permanently deletes the
builder session while job receipts are still needed to make cleanup and restart
recovery idempotent. Only the workflow token and builder-specific MCP config
live in the builder runtime.

The job contains:

- workflow, builder-session, and workspace IDs;
- original message and Landing launch choices (project/worktree and security
  policy for the destination);
- resolved generator identity and model-pool snapshot;
- settings revision/time and workspace revision/time;
- probe records by target;
- staged catalog acquisitions and resolved resource IDs;
- latest validated plan;
- committed team ID and destination session ID, when allocated;
- state, attempt number, timestamps, last structured error, and cancellation;
- idempotency receipts for mutating tool calls.

The state machine is monotonic except that a recoverable failure returns to the
last safe phase:

```text
created -> probing -> planning -> validating -> committing
        -> launching -> delivering -> delivered -> cleaning -> complete

any non-terminal state -> failed(recoverable phase + error)
any pre-commit state   -> cancelled
```

`complete` means the builder session has been removed. `delivered` alone is not
enough to delete it; cleanup first waits for the finalize tool response to be
flushed and the builder turn to become idle. Completion removes staging and
compacts `job.json` to a bounded-retention tombstone containing only workflow,
team, destination-session, delivery, and cleanup receipts; it drops the
original prompt, plan, probes, tokens, and catalog details. Pre-commit
cancellation removes the workflow directory only after its builder and staging
cleanup succeeds.

## Builder session and skill

The coordinator resolves `AiFeatureId.teamGenerate` to a
`SimpleLaunchIdentity`, creates the builder through the normal
`requestCreateAndOpenSession` path, and opens it through `WorkbenchCubit`.
This retains normal CLI provisioning, history, reconnect, remote execution, and
terminal behavior.

The selected CLI must expose the capabilities needed by this workflow. Add a
registry-level workflow compatibility check composed from existing session,
skill, and MCP capabilities; do not branch on `CliTool` in Landing or the
coordinator.

The built-in Team Builder capability pack supplies:

- a stable built-in expert key;
- the internal `team-builder` skill;
- the Team Composer MCP contribution;
- access to the existing Catalog MCP in generation scope.

The skill instructs the agent to:

1. read generation context and the task;
2. wait for or request target probes;
3. design the smallest non-overlapping roster with exactly one lead;
4. assign only listed presets and targets;
5. search/acquire the minimum useful team resources;
6. validate, correct every reported issue, then finalize exactly once;
7. never edit TeamPilot profile/session/workspace files directly;
8. stop after finalization is accepted and let the app perform handoff.

The builder launch policy grants workspace read access needed for analysis but
does not grant arbitrary control-plane writes. Intended mutations go through
the two MCPs, whose schemas and session authorization remain the source of
truth even if the model ignores its skill.

## Catalog MCP generation scope

The current Catalog MCP supports skills, plugins, and MCP resources, but only
accepts workspace binding. Extend its request scope with a generation binding:

```text
bind_to: generation
workflow_id: <current authorized workflow>
```

The workflow ID is derived and verified from the MCP session; callers cannot
use it to address another job. Existing workspace behavior remains unchanged.

Generation acquisition follows these rules:

1. Search/read use existing catalog modules and policies.
2. If an ID is already installed, record a reference in the job without
   changing workspace bindings.
3. New acquisitions download and validate into a workflow staging area.
4. A staged item is not visible as an installed global resource until commit.
5. Commit promotes/deduplicates staged items under the same repository locks
   used by normal installation, then writes the resulting IDs to TeamProfile.
6. Cancel removes unpromoted staging.
7. Credentials, OAuth, license acceptance, or other required interaction return
   a structured `user_action_required` result. The UI opens the existing flow;
   completion resumes the same acquisition receipt.
8. Resource installation does not implicitly add IDs to the workspace bundle.

Plugins may contribute skills or MCP servers through existing resource
assemblers. Final validation operates on the resolved team bundle, not just the
raw top-level IDs.

## Team Composer MCP

Expose a dedicated server name, versioned tool schemas, and only the following
workflow-scoped tools.

### `get_generation_context`

Returns immutable facts:

- original task;
- desired native/mixed mode;
- effective ranked model-pool snapshot;
- workspace folders and folder-backed target IDs;
- current probe status/results;
- existing and staged catalog resources;
- relevant roster, placement, and launch constraints;
- schema version expected by validation/finalization.

It never returns provider credentials, SSH secrets, MCP credentials, or paths
outside the workflow's allowed roots.

### `probe_workspace_targets`

Starts or refreshes bounded read-only probes. It accepts no arbitrary host. The
server derives candidates from the live workspace folder catalog. The default
call probes every candidate and returns progress/results. Repeated calls reuse
fresh cached facts.

### `validate_team_plan`

Purely validates a full plan and returns field-addressed errors/warnings plus a
normalized preview. It performs no persistence and can be called repeatedly.

### `finalize_team_generation`

Accepts the full plan, a validation revision, and an idempotency key. It
revalidates against live settings/workspace/catalog state, then starts commit
and handoff. Repeating the same call returns the same receipt, team ID, and
destination session ID. A different plan after commit is rejected with a
structured immutable-commit error.

There is no general `create_team`, `delete_session`, or `switch_session` tool.
The finalizer can operate only on its own workflow, and application services
choose the generated destination.

## Machine probes

`TeamTargetProbeService` derives targets from `workspace.folders`, resolving
them through existing runtime-target services. Saved SSH profiles that do not
back a workspace folder are excluded.

For each candidate it records, with timeouts and per-field errors:

- reachability and runtime kind;
- remote OS when applicable;
- accessibility of the target's workspace folders;
- required CLI executable availability and version;
- basic CPU count, memory, and free-disk facts when cheaply available;
- probe timestamp and freshness.

Required CLIs are the native CLI in native mode and the distinct CLIs in the
effective mixed pool. Probes are read-only and never install or upgrade a CLI.
One unreachable target does not fail the whole context; it becomes an
unavailable scheduling option.

The plan may assign multiple replicas of one member type across targets. It
uses instance counts by target, which normalizes to `MemberPlacementByTarget`
and then existing `memberTargetsFromMemberPlacement` semantics. The model does
not invent instance IDs.

## Generated team plan

The versioned MCP schema contains:

```json
{
  "schemaVersion": 1,
  "team": {
    "name": "auth-revamp",
    "description": "...",
    "mode": "mixed"
  },
  "members": [
    {
      "name": "team-lead",
      "role": "coordinator",
      "responsibilities": "...",
      "workingMethod": "...",
      "presetId": "preset-strong",
      "replicas": 1,
      "placement": {"local": 1}
    }
  ],
  "resources": {
    "skillIds": [],
    "pluginIds": [],
    "mcpServerIds": []
  }
}
```

Member IDs are derived with `TeamMemberNaming`, not trusted from model output.
The lead is always a singleton. Worker replica counts equal the sum of their
placement counts. A missing member preset normalizes to
`TeamProfile.inheritPresetId`; an unknown preset is an error rather than a
silent fallback. The plan repeats the frozen team mode so validation errors are
easy to understand, but it cannot change that mode. The team default preset is
always derived from the first effective pool entry in the job snapshot and is
not part of model output.

### Validation

`GeneratedTeamPlanValidator` checks, without mutation:

1. supported schema version and bounded field sizes;
2. a non-empty team name and exactly one `team-lead`;
3. 2–5 distinct, non-overlapping member types and valid normalized IDs;
4. plan mode exactly matches the job's frozen generation mode;
5. every explicit preset exists in the frozen effective pool;
6. native mode uses one native-capable CLI and every preset matches it;
7. mixed mode synchronizes each explicit preset's CLI into roster overrides;
8. resource IDs are installed, staged by this job, or resolved plugin
   contributions;
9. target IDs are current folder-backed targets with successful required facts;
10. replicas and placement counts agree; the lead count is exactly one;
11. `leadPlacementValid`, mixed initialization, and folder ownership rules;
12. remote CLI requirements from existing launch readiness services;
13. final `TeamConfigLaunchValidator` compatibility after constructing a
    non-persisted TeamProfile preview.

Warnings may cover inefficient concentration, a lower-ranked lead preset, or a
partially probed optional worker target. Warnings do not bypass hard launch
constraints.

## Commit transaction

`GeneratedTeamCommitService` is a repository-level domain service. It does not
depend on whichever team is selected in `LaunchProfileCubit`.

Commit uses the workflow ID as its idempotency key:

1. acquire a workflow commit lock;
2. reload and revalidate job, workspace, presets, probes, and resources;
3. reserve a collision-free display name and canonical team ID, suffixing a
   generated name rather than failing on a normal name collision;
4. stage generated member personas and stable local-expert keys;
5. promote/deduplicate staged catalog resources;
6. construct roster slots:
   - explicit preset -> `activePresetId`;
   - mixed explicit preset -> also `cli: preset.cli`;
   - inherit -> `TeamProfile.inheritPresetId`;
   - never duplicate provider/model/effort into member overrides;
7. persist TeamProfile with the first effective pool preset as its fixed
   default, plus resources, mode, description, and roster;
8. normalize the generated placement through
   `prepareMemberPlacementSave`-equivalent domain logic and persist workspace
   member targets/initialization;
9. await profile provisioning and team resource sync;
10. record the committed team ID before releasing the lock;
11. publish state updates to `LaunchProfileCubit` and `ChatCubit` through
    explicit refresh/patch APIs.

Because multiple files and catalogs cannot share one filesystem transaction,
the job is a write-ahead transaction record. Each step records a receipt before
the next begins. Retry resumes from receipts and verifies materialized content.
Pre-profile failures compensate staged expert/resources. Once the profile is
committed, recovery completes forward rather than deleting a possibly visible
team.

This service supersedes calling `LaunchProfileCubit.addTeam()` followed by
`setTeamActivePreset()`: that API returns only `bool`, rejects display-name
collisions, depends on selected state for later mutations, and would require
multiple non-idempotent writes.

## Destination session and prompt delivery

`TeamGenerationHandoffService` consumes a committed job:

1. select/publish the generated team and update Landing recent-team state;
2. create the destination through the existing
   `ChatCubit.requestCreateAndOpenSession(SessionCreateRequest(...))` pipeline;
3. store `targetSessionId` in the job before retryable connection work;
4. open it with `WorkbenchCubit.openSession` so the user sees launch progress;
5. wait with `memberMaterializer.ensureMemberInputReady` for the generated lead;
6. persist the normal pending history bubble and deliver the exact original
   Landing message through `deliverUserCommandToMember`;
7. mark the job delivered only after delivery succeeds.

The original Landing message is snapshotted before creating the builder. The
builder can inspect it but cannot replace it. Attachments and composed file
references use the same text produced by the Landing `ComposeClip` path.

Destination creation and delivery use stored IDs on retry. They never create a
second destination session for the same workflow. Existing remote CLI and
session launch errors retain their normal typed status and user feedback.

### Safe builder deletion

The finalizer's MCP response must reach the builder CLI before its session is
deleted. Cleanup therefore waits for all three signals:

1. destination prompt delivery succeeded;
2. the finalize MCP response was flushed by the transport;
3. the builder turn reached idle/quiet or a bounded post-response grace
   confirmed no transcript write is pending.

Cleanup then deletes the builder through existing `ChatCubit`/
`SessionRepository` session-deletion paths, removes the workflow staging
directory, scrubs sensitive job fields, and compacts the durable job to its
terminal tombstone. If cleanup fails, recovery retries from the recorded
receipts; it never re-delivers the destination prompt.

## Error handling and recovery

Errors use stable codes plus user-localized presentation. Examples:

| Code | Recovery |
|---|---|
| `generator_not_configured` | Open AI feature configuration |
| `model_pool_empty` | Open generation settings |
| `generator_capability_missing` | Select a compatible generator preset |
| `target_probe_failed` | Agent chooses another target or user fixes connection |
| `remote_cli_missing` | Reassign member or use existing remote CLI remediation |
| `catalog_user_action_required` | Complete auth/config UI, then resume receipt |
| `plan_invalid` | Agent receives field errors and resubmits |
| `workspace_changed` | Refresh context/probes and revalidate |
| `commit_conflict` | Reload receipt; use reserved team ID |
| `destination_launch_failed` | Keep both sessions; retry same target session |
| `prompt_delivery_failed` | Existing failed-message UI plus idempotent retry |

At bootstrap, the coordinator scans durable non-terminal jobs first, then
verifies each associated builder session has `purpose == teamGeneration` and a
matching workflow ID. An orphaned pre-commit job is safely cancelled and
cleaned; an orphaned post-commit job resumes forward from receipts without
recreating the team or destination session. A missing/corrupt job never grants
MCP write access; the UI offers safe builder deletion and a recovery report.

## UI structure

Keep the already-large `unbound_compose_body.dart` focused by extracting
generation behavior:

- menu specification remains in `team_landing_chip_menu.dart`;
- global settings UI lives in
  `workspace_landing_generate_settings_dialog.dart` and uses `Tp*` controls;
- Landing generation state/preflight and start actions live in a focused
  controller/service rather than additional IO inside `build()`;
- builder workflow chrome is a route/session-specific widget, while reusable
  status primitives belong in `shared_ui` only if another route also uses them.

The settings dialog contains:

- generation AI row using `AiFeatureConfigRow` /
  `AiFeatureConfigureDialog` for `teamGenerate`;
- native/mixed selection and native CLI when relevant;
- ordered model-pool entries showing preset summary, description, and tags;
- add from existing presets or create via `CliPresetEditDialog`;
- reorder/remove actions and visible broken-reference states;
- a note that the builder may probe workspace targets and acquire team
  resources.

Native mode visually filters the effective pool by native CLI without deleting
incompatible stored entries; switching back to mixed restores them.

## Compatibility with existing generation

Landing generation does not extend:

- `team_config_prompt.dart` or its native/mixed builders;
- `team_config_draft.dart`;
- `team_draft_roster_mapper.dart`;
- `TeamConfigGenerator.generate` / `generateStreaming`.

Those files remain the implementation of the existing New Team modal. The new
MCP tool schema, validator, and commit service are independent, so accepting
agentic features does not change legacy draft parsing or prompt contracts.

## Security

1. Workflow token plus session purpose and IDs gate every Team Composer write.
2. Catalog generation binding is derived from authenticated session context;
   model arguments cannot nominate another workflow.
3. Target probes accept only live workspace-backed IDs and use read-only
   commands with timeouts and output limits.
4. Team plans have size/count limits; unknown keys are ignored or rejected per
   schema version, never treated as filesystem paths.
5. Resource acquisition obeys catalog path sandbox, registry policy, URL checks,
   and existing extension restrictions.
6. The model never receives provider, SSH, or MCP secrets.
7. Commit revalidates all model-provided IDs against live repositories.
8. Session navigation and deletion are application effects, not general MCP
   tools.

## Testing

### Models and stores

- generation-settings JSON round trip, ordering, duplicate normalization,
  deterministic first-wins behavior, broken preset preservation, native
  filtering;
- Landing prefs/context `generateLaunch` round trip and invariant;
- AppSession purpose/workflow serialization and old-session fallback;
- generation-job state transitions, receipts, cancellation, corruption, and
  atomic recovery outside the builder-session directory;

### MCP and authorization

- Team Composer tools are advertised only to authorized builder sessions;
- wrong purpose/workflow/token/workspace is rejected;
- Catalog `bind_to: generation` stages without workspace binding;
- repeated acquisition/finalize idempotency;
- MCP response-flushed signal precedes builder cleanup.

### Probes and validation

- all folder-backed local/WSL/SSH targets are probed with fakes;
- non-workspace targets are excluded;
- partial timeout/unreachable results remain structured;
- native and mixed preset/CLI rules;
- valid/invalid resources, replicas, placements, lead rules, and workspace
  changes;
- preview passes through existing team launch validation.

### Commit and recovery

- collision-safe generated team naming;
- explicit preset overrides, mixed CLI synchronization, and inherit behavior;
- staged expert/resource promotion and compensation;
- placement persistence marks mixed initialization;
- failure after each receipt resumes without duplicate team/session/resource;
- completion removes sensitive staging and leaves only the bounded tombstone;
- orphaned pre-commit and post-commit jobs take their respective recovery paths;
- cubit state updates follow persisted repositories.

### Handoff and widgets

- Landing generate mode opens builder rather than invoking headless generation;
- builder session becomes visible immediately and can be cancelled;
- destination tab opens through normal session launch;
- exact original prompt is delivered once to the lead;
- delivery failure retains builder;
- successful delivery plus response flush/idle deletes builder;
- restart resumes unfinished workflows;
- global settings dialog supports add/edit/reorder/delete and broken presets.

Use `setUpTestAppStorage()` / `tearDownTestAppStorage()` for tests touching
`AppStorage`. Subprocess, SSH, catalog acquisition, and PTY readiness must be
constructor-injected fakes. New end-to-end CLI coverage is tagged
`@Tags(['integration'])`.

Before completion:

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart
```

## Delivery boundaries

This is one product workflow but should be implemented in dependency order:

1. persistent settings, session purpose, workflow job, and authorization;
2. builder capability pack plus Team Composer context/probe/validation;
3. Catalog generation staging and transactional team commit;
4. destination handoff, cleanup/recovery, and Landing UX;
5. integration coverage and legacy regression verification.

Each boundary must leave stored data forward-compatible and its services
independently testable. The implementation plan may split these into reviewable
commits, but no phase may expose an unvalidated model-to-control-plane write.
