# Team Builder Skill Optimization Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make TeamPilot's visible Team Builder use the correct managed skill, Claude-inspired collaboration rules, and the normal user-message history/delivery pipeline before handing the original prompt to the generated lead.

**Architecture:** Build on the existing feature/agentic-team-generate-launch generation foundation. Keep Team Composer MCP as the planning API and TeamBus as runtime coordination; do not introduce native Claude TeamCreate. The builder kickoff is a synthetic user message persisted through the same history and tracked PTY-delivery seams used by ordinary input-box messages.

**Tech Stack:** Flutter/Dart, flutter_bloc, TeamPilot resource contribution providers, durable JSON stores, Team Composer MCP, CLI capability registry, PromptDeliveryCoordinator, and Flutter/Dart tests.

## Global Constraints

- Implement against feature/agentic-team-generate-launch (f7000aeab plus its current uncommitted wiring), or port that foundation first; do not reset or overwrite its uncommitted files.
- Team Builder uses Team Composer MCP and never calls native TeamCreate, TaskCreate, Agent, or SendMessage to create the TeamPilot team.
- The generated roster contains 2–5 distinct roles and exactly one canonical team-lead.
- team-builder resolves through ManagedTeamBuilderSkillProvider, never through obra/superpowers:team-builder.
- Kickoff and handoff messages use normal history persistence, UI pending bubbles, stable delivery IDs, PTY delivery, and transcript reconciliation.
- Ordinary MCP errors are returned to the builder agent; the coordinator adds no fixed MCP retry loop or defensive preflight gate.
- No workflow phase-status row or phase-status chat bubbles are added.
- Edit only client/lib/l10n/app_en.arb and client/lib/l10n/app_zh.arb for localization source changes; regenerate checked-in output.
- Preserve unrelated existing worktree changes, including automation tests and the third_party/fastforge submodule state.
- Unless a command includes another directory, run Flutter/Dart test commands from the generation worktree's client directory.
- Before completion, run cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart.

## Implementation Baseline and File Map

The generation foundation exists on feature/agentic-team-generate-launch, not on the current session-tab-bar branch. Before implementation, inspect and preserve the existing uncommitted wiring in:

- client/lib/app/team_generation_graph.dart
- client/lib/cubits/team/cubit_team_generation_session_port.dart
- client/lib/services/team_generation/runtime_team_target_probe_runner.dart
- client/lib/app/app_shell.dart
- client/lib/cubits/chat_cubit.dart
- client/lib/cubits/chat/tab_member_pty_delivery.dart
- client/lib/cubits/chat/tab_session_runtime_coordinator.dart
- client/lib/services/storage/runtime_target_registry.dart
- client/lib/services/team_generation/models/team_generation_job.dart
- client/lib/services/team_generation/team_generation_authorizer.dart
- client/lib/services/team_generation/team_generation_coordinator.dart

Do not reset or overwrite these uncommitted files. Reconcile them with the plan.

## Task 1: Remove the Unwanted Builder Phase-Status UI

**Files:**

- Delete: client/lib/pages/chat/team_generation_builder_status.dart
- Delete: client/test/pages/chat/team_generation_builder_status_test.dart
- Modify: client/lib/l10n/app_en.arb
- Modify: client/lib/l10n/app_zh.arb
- Modify: client/test/l10n/team_generation_l10n_test.dart
- Regenerate: checked-in client/lib/l10n/app_localizations*.dart

**Interfaces:**

- Consumes: durable TeamGenerationPhase values used by services and recovery.
- Produces: no builder phase widget or phase-status localization contract; job phases remain persistence and diagnostics data.

- [ ] Step 1: Confirm the widget is not needed by another route.

~~~bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/agentic-team-generate-launch
rg -n "TeamGenerationBuilderStatus|team_generation_builder_status|teamGeneratePhase" client/lib client/test
~~~

Expected: references are limited to the widget, its test, and phase-only localization assertions.

- [ ] Step 2: Delete the widget and its widget test. Do not remove generation services or job phase enums.

- [ ] Step 3: Remove only phase-only localization entries. Delete teamGeneratePhaseCreated through teamGeneratePhaseFailed from both ARB files and their l10n test assertions. Keep action/cancellation strings still used by another generation surface.

- [ ] Step 4: Regenerate localization output.

~~~bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/agentic-team-generate-launch/client
flutter gen-l10n
~~~

- [ ] Step 5: Verify no phase-status UI remains.

~~~bash
flutter test test/l10n/team_generation_l10n_test.dart
rg -n "TeamGenerationBuilderStatus|teamGeneratePhase" client/lib client/test
~~~

Expected: the test passes and the second command returns no references.

- [ ] Step 6: Commit.

~~~bash
git add client/lib/pages/chat/team_generation_builder_status.dart client/test/pages/chat/team_generation_builder_status_test.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/l10n/team_generation_l10n_test.dart client/lib/l10n
git commit -m "refactor(team-generation): remove builder phase status chrome"
~~~

## Task 2: Correct Managed Team Builder Skill Dependency Resolution

**Files:**

- Modify: client/lib/services/team_hub/builtin_team_templates.dart
- Modify: client/lib/services/expert_hub/builtin_member_templates.dart
- Test: client/test/services/expert_hub/builtin_member_templates_test.dart
- Test: client/test/services/team_generation/managed_team_builder_skill_provider_test.dart
- Test: client/test/services/session/team_generation_session_resources_test.dart

**Interfaces:**

- Consumes: existing SkillDependencyRef, ResourceProviderSet, and ManagedTeamBuilderSkillProvider.skillId.
- Produces: the built-in Team Builder expert's effective skill ID team-builder; ordinary Superpowers dependencies retain their catalog identity.

- [ ] Step 1: Add a failing assertion that the Team Builder expert has one skill dependency whose expectedLocalId is team-builder and whose repository fields are empty. Assert that the default expert still resolves using-superpowers to the Superpowers catalog identity.

- [ ] Step 2: Run the focused test and observe the current failure.

~~~bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/agentic-team-generate-launch/client
flutter test test/services/expert_hub/builtin_member_templates_test.dart
~~~

Expected: failure because the generic _skills helper converts team-builder into obra/superpowers:team-builder.

- [ ] Step 3: Add the smallest explicit managed-skill helper beside superpowersSkillDep in builtin_team_templates.dart. The Team Builder entry must use the managed helper. It must carry id team-builder and no repository source fields. All other built-ins keep superpowersSkillDep.

- [ ] Step 4: Assert provider selection and isolation. A teamGeneration session receives ManagedTeamBuilderSkillProvider; an ordinary Simple session does not. The provider materializes a contribution with ID team-builder.

- [ ] Step 5: Run focused tests.

~~~bash
flutter test test/services/expert_hub/builtin_member_templates_test.dart test/services/team_generation/managed_team_builder_skill_provider_test.dart test/services/session/team_generation_session_resources_test.dart
~~~

Expected: pass, with no Unknown catalog skill id obra/superpowers:team-builder diagnostic for a builder session.

- [ ] Step 6: Commit.

~~~bash
git add client/lib/services/team_hub/builtin_team_templates.dart client/lib/services/expert_hub/builtin_member_templates.dart client/test/services/expert_hub/builtin_member_templates_test.dart client/test/services/team_generation/managed_team_builder_skill_provider_test.dart client/test/services/session/team_generation_session_resources_test.dart
git commit -m "fix(team-generation): resolve managed builder skill directly"
~~~

## Task 3: Rewrite the Managed Team Builder Skill

**Files:**

- Modify: client/lib/services/team_generation/providers/team_builder_skill_md.dart
- Modify: client/lib/services/team_generation/managed_skills/team-builder/SKILL.md
- Test: client/test/services/team_generation/managed_team_builder_skill_provider_test.dart

**Interfaces:**

- Consumes: Team Composer MCP tools get_generation_context, probe_workspace_targets, validate_team_plan, and finalize_team_generation; Catalog MCP resource search/acquisition.
- Produces: a byte-identical managed skill artifact containing the Claude-inspired collaboration protocol adapted to TeamPilot.

- [ ] Step 1: Add content assertions for all required markers: get_generation_context, probe_workspace_targets, validate_team_plan, finalize_team_generation, 2–5, team-lead, Catalog MCP, Never edit TeamPilot JSON manifests, and stop-after-finalize wording. Assert that the skill does not tell the builder to call native TeamCreate.

- [ ] Step 2: Run the provider test before changing the skill.

~~~bash
flutter test test/services/team_generation/managed_team_builder_skill_provider_test.dart
~~~

Expected: failure for the new markers.

- [ ] Step 3: Rewrite the skill in this order:

1. Read generation context first.
2. Choose the smallest useful 2–5 role roster with exactly one team-lead.
3. Give every role non-overlapping responsibilities, inputs, outputs, launch configuration, and required resources.
4. Use Catalog MCP for search, read, and generation-scoped acquisition.
5. Probe workspace targets before assigning machines.
6. Treat model-pool rank 1 as strongest and use frozen context values.
7. Validate, inspect returned errors, correct the plan, and retry as an agent decision.
8. Finalize only after validation succeeds and stop after acceptance.

Hard rules prohibit direct manifest edits, credential handling, original-task delivery by the builder, native TeamCreate usage, and post-finalize implementation. MCP failures are ordinary tool errors that the builder agent can inspect and recover from; do not encode a coordinator retry count.

- [ ] Step 4: Synchronize managed_skills/team-builder/SKILL.md exactly with the Dart source string.

- [ ] Step 5: Run the provider test and byte-identity test.

~~~bash
flutter test test/services/team_generation/managed_team_builder_skill_provider_test.dart
~~~

Expected: pass.

- [ ] Step 6: Commit.

~~~bash
git add client/lib/services/team_generation/providers/team_builder_skill_md.dart client/lib/services/team_generation/managed_skills/team-builder/SKILL.md client/test/services/team_generation/managed_team_builder_skill_provider_test.dart
git commit -m "feat(team-generation): strengthen managed builder workflow skill"
~~~

## Task 4: Route Synthetic Kickoff Through Normal History and Delivery

**Files:**

- Modify: client/lib/services/team_generation/team_generation_session_port.dart
- Modify: client/lib/cubits/team/cubit_team_generation_session_port.dart
- Modify: client/lib/services/team_generation/team_generation_coordinator.dart
- Modify: client/lib/services/prompt_delivery/prompt_delivery.dart
- Modify: client/lib/models/failed_message_record.dart
- Modify: client/lib/cubits/ai_history_seat.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Modify: client/lib/cubits/chat/tab_session_runtime_coordinator.dart
- Modify: client/lib/cubits/chat/tab_member_pty_delivery.dart
- Test: client/test/services/prompt_delivery/prompt_delivery_coordinator_test.dart
- Test: client/test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
- Test: client/test/services/team_generation/team_generation_coordinator_test.dart
- Test: client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart

**Interfaces:**

- Consumes: ChatCubit.persistHistoryPending, PromptDeliveryCoordinator.submit, PromptDeliveryRequest.deliveryId, tracked PTY delivery, and the generation session-port history seed seam.
- Produces: a history seed API with a caller-supplied delivery ID, plus buildTeamGenerationKickoff(originalPrompt) as one persisted synthetic user message and one tracked PTY submission using the stable kickoff delivery ID.

- [ ] Step 1: Add a failing test asserting this order for a builder kickoff:

~~~text
persistHistoryPending(builderSessionId, builderMemberId, kickoff)
deliverTracked(builderSessionId, builderMemberId, kickoff, kickoffId)
~~~

Assert that the history text equals the exact kickoff and kickoffId equals teamGenerationStableId with the workflow ID.

- [ ] Step 2: Add an idempotency assertion. Running the same workflow kickoff twice reuses the existing delivery record and does not create a second PTY submission or pending bubble.

- [ ] Step 3: Run focused tests before implementation.

~~~bash
flutter test test/services/team_generation/team_generation_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
~~~

Expected: failure because the coordinator currently sends tracked PTY input without seeding TeamPilot history.

- [ ] Step 4: Extend FailedMessageRecord, AiHistorySeat.persistPendingUser, and ChatCubit.persistHistoryPending with an optional deliveryId while preserving random pending IDs for ordinary input. For generation sends, use the stable workflow delivery ID as the pending record correlation field. Route this through the generation session-port adapter. Resolve the Simple builder history member exactly as the normal landing path does. Do not simulate the input widget. Keep the existing PromptDeliveryCoordinator state machine.

- [ ] Step 5: Update coordinator ordering. After the builder input surface is ready and before deliverTracked, persist the kickoff history record. Mark builderKickoff only after tracked delivery reports submission, using the same workflow ID and kickoff ID on resume.

- [ ] Step 6: Run focused tests including normal landing regression coverage.

~~~bash
flutter test test/services/team_generation/team_generation_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_idempotency_test.dart test/pages/home_workspace/workspace/workspace_session_actions_test.dart
~~~

Expected: pass with one UI pending bubble, one CLI submission, and stable delivery state across restart fixtures.

- [ ] Step 7: Commit.

~~~bash
git add client/lib/services/team_generation/team_generation_session_port.dart client/lib/cubits/team/cubit_team_generation_session_port.dart client/lib/services/team_generation/team_generation_coordinator.dart client/lib/services/prompt_delivery/prompt_delivery.dart client/lib/cubits/chat_cubit.dart client/lib/cubits/chat/tab_session_runtime_coordinator.dart client/lib/cubits/chat/tab_member_pty_delivery.dart client/test/services/prompt_delivery client/test/services/team_generation/team_generation_coordinator_test.dart client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart
git commit -m "fix(team-generation): persist builder kickoff as user message"
~~~

## Task 5: Deliver the Raw Original Prompt Through the Same Contract at Handoff

**Files:**

- Modify: client/lib/services/team_generation/team_generation_handoff_service.dart
- Modify: client/lib/cubits/team/cubit_team_generation_session_port.dart
- Modify: client/lib/services/team_generation/team_generation_session_port.dart
- Modify: client/lib/models/failed_message_record.dart
- Modify: client/lib/cubits/ai_history_seat.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Test: client/test/services/team_generation/team_generation_handoff_service_test.dart
- Test: client/test/services/team_generation/team_generation_coordinator_test.dart

**Interfaces:**

- Consumes: immutable TeamGenerationJob.originalPrompt, generated lead identity, stable handoff delivery ID, and normal history/prompt delivery seams.
- Produces: exactly one destination lead user message whose text equals originalPrompt, without the Builder wrapper.

- [ ] Step 1: Add a failing handoff assertion that destination history receives the raw originalPrompt, while the tracked prompt request uses the same raw string and reserved delivery ID.

- [ ] Step 2: Run the handoff test before implementation.

~~~bash
flutter test test/services/team_generation/team_generation_handoff_service_test.dart
~~~

Expected: failure if history is absent or the kickoff wrapper is reused.

- [ ] Step 3: Add seedUserHistory to TeamGenerationSessionPort with sessionId, memberId, text, and deliveryId parameters. Implement it through ChatCubit.persistHistoryPending and the existing AiHistorySeat pending queue. Seed destination lead history once before issuing the tracked PTY submit; reuse the record identified by the reserved delivery ID for a resumed workflow.

- [ ] Step 4: Do not add MCP retry loops while changing handoff. Handoff consumes the accepted finalized plan and reports actual destination/session delivery outcomes.

- [ ] Step 5: Run handoff and idempotency tests.

~~~bash
flutter test test/services/team_generation/team_generation_handoff_service_test.dart test/services/team_generation/team_generation_coordinator_test.dart test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
~~~

Expected: pass with one raw original prompt on the lead and no duplicate after resumed handoff.

- [ ] Step 6: Commit.

~~~bash
git add client/lib/services/team_generation/team_generation_handoff_service.dart client/lib/cubits/team/cubit_team_generation_session_port.dart client/lib/services/team_generation/team_generation_session_port.dart client/test/services/team_generation/team_generation_handoff_service_test.dart client/test/services/team_generation/team_generation_coordinator_test.dart
git commit -m "fix(team-generation): show original prompt on generated lead"
~~~

## Task 6: Reconcile Generation Wiring Without Defensive Preflight

**Files:**

- Modify: client/lib/app/app_shell.dart
- Modify: client/lib/app/team_generation_graph.dart
- Modify: client/lib/services/session/session_lifecycle_service.dart
- Modify: client/lib/services/launch/session_shell_connector.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Modify: client/lib/pages/home_workspace/workspace/workspace_session_actions.dart
- Modify: client/lib/services/team_generation/team_generation_coordinator.dart
- Test: client/test/services/session/team_generation_session_resources_test.dart
- Test: client/test/services/team_generation/team_generation_coordinator_test.dart
- Test: client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart

**Interfaces:**

- Consumes: existing generation graph, injected resource providers, Team Composer gateway, and landing generate-and-launch action.
- Produces: one wired builder path that does not silently fall back to ordinary Simple launch; ordinary Simple and Team launches remain unchanged.

- [ ] Step 1: Add a wiring regression test asserting one TeamGenerationCoordinator, one Team Composer handler, and ManagedTeamBuilderSkillProvider only for builder sessions.

- [ ] Step 2: Run the regression tests.

~~~bash
flutter test test/services/session/team_generation_session_resources_test.dart test/services/team_generation/team_generation_coordinator_test.dart test/pages/home_workspace/workspace/workspace_session_actions_test.dart
~~~

Expected: failure only for missing managed skill identity, kickoff history, or the known uncommitted wiring gap.

- [ ] Step 3: Keep buildTeamGenerationGraph as the composition root. Ensure app_shell attaches the Composer handler and token issuer once, and SessionLifecycleService receives injected providers through ResourceProviderSet. Do not add a second singleton or scatter CLI-specific conditionals.

- [ ] Step 4: Remove the silent plain-session fallback from the landing generation branch. If the graph cannot be constructed, use the existing launch-error path and preserve the generation job; do not call ordinary submitWorkspaceLandingMessage as if Simple mode was selected.

- [ ] Step 5: Keep MCP failures agent-owned. The graph exposes Team Composer MCP and returns real tool errors; it does not add retry counters, speculative provider checks, or a replacement planner.

- [ ] Step 6: Run the composition and landing tests again.

~~~bash
flutter test test/services/session/team_generation_session_resources_test.dart test/services/team_generation/team_generation_coordinator_test.dart test/pages/home_workspace/workspace/workspace_session_actions_test.dart
~~~

Expected: pass, with generation remaining generation-scoped and ordinary landing launches unchanged.

- [ ] Step 7: Commit.

~~~bash
git add client/lib/app/app_shell.dart client/lib/app/team_generation_graph.dart client/lib/services/session/session_lifecycle_service.dart client/lib/services/launch/session_shell_connector.dart client/lib/cubits/chat_cubit.dart client/lib/pages/home_workspace/workspace/workspace_session_actions.dart client/lib/services/team_generation/team_generation_coordinator.dart client/test/services/session/team_generation_session_resources_test.dart client/test/services/team_generation/team_generation_coordinator_test.dart client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart
git commit -m "fix(team-generation): require wired builder workflow"
~~~

## Task 7: Add End-to-End Workflow Regression Coverage

**Files:**

- Test: client/test/services/team_generation/team_generation_workflow_executor_test.dart
- Test: client/test/services/team_generation/team_generation_handoff_service_test.dart
- Test: client/test/services/team_generation/team_generation_coordinator_test.dart
- Test: client/test/services/team_generation/managed_team_builder_skill_provider_test.dart
- Test: client/test/services/prompt_delivery/prompt_delivery_idempotency_test.dart

**Interfaces:**

- Consumes: completed managed skill, generation graph, coordinator, Composer handler, prompt-delivery store, and fake session/PTY adapters.
- Produces: regression evidence for the complete user-visible contract without real CLI binaries or network credentials.

- [ ] Step 1: Add a fake Composer conversation fixture with this sequence:

~~~text
get_generation_context
probe_workspace_targets
validate_team_plan -> valid: false
validate_team_plan -> valid: true
finalize_team_generation -> accepted
~~~

Assert that the coordinator does not invoke an MCP retry wrapper; the second validation call is made by the simulated builder conversation.

- [ ] Step 2: Assert complete message visibility. The builder has one kickoff record containing the wrapper and original request. The destination lead has one record containing exactly the raw original request.

- [ ] Step 3: Assert resource visibility. The builder runtime has team-builder/SKILL.md, Catalog MCP, and Team Composer MCP. The generated destination does not inherit the builder-only managed skill unless explicitly bound by its plan.

- [ ] Step 4: Simulate destination missingTeamMember after finalize and assert the job remains recoverable with builder/session evidence intact. Keep ordinary MCP tool errors agent-recoverable.

- [ ] Step 5: Run the fake workflow tests.

~~~bash
flutter test test/services/team_generation/team_generation_workflow_executor_test.dart test/services/team_generation/team_generation_handoff_service_test.dart test/services/team_generation/team_generation_coordinator_test.dart test/services/team_generation/managed_team_builder_skill_provider_test.dart test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
~~~

Expected: pass with no phase-status widget dependency and no native TeamCreate dependency.

- [ ] Step 6: Commit.

~~~bash
git add client/test/services/team_generation client/test/services/prompt_delivery/prompt_delivery_idempotency_test.dart
git commit -m "test(team-generation): cover builder skill and message handoff"
~~~

## Task 8: Full Verification and Runtime Smoke Test

**Files:**

- Files: none intended; return a failing command to its owning task instead of making unrelated cleanup changes.
- Test: full Flutter analyzer, repository test runner, and one local generation smoke test.

- [ ] Step 1: Format and analyze.

~~~bash
cd /home/hhoa/git/hhoa/teampilot/.worktrees/agentic-team-generate-launch/client
dart format lib test
flutter analyze --no-fatal-infos --no-fatal-warnings
~~~

- [ ] Step 2: Run the repository test runner.

~~~bash
dart run tool/run_tests.dart
~~~

- [ ] Step 3: Perform one local generate-and-launch smoke test and verify:

1. a temporary visible Simple Builder session is created;
2. one fixed kickoff user bubble appears;
3. the builder runtime contains team-builder/SKILL.md;
4. the builder runtime contains Team Composer MCP;
5. the builder makes context, probe, validate, and finalize calls;
6. a destination Team session opens;
7. the lead shows the exact original prompt as one user bubble;
8. the Builder is cleaned up only after successful handoff;
9. no phase-status row appears.

- [ ] Step 4: Inspect the final diff and worktree.

~~~bash
git diff --check
git status --short
git log -8 --oneline --decorate
~~~

Expected: only planned commits are present on the generation implementation baseline; unrelated user changes remain untouched.

- [ ] Step 5: Report exact analyzer/test commands and outcomes, smoke-test workflow/session IDs if available, and any environment-only limitations.
