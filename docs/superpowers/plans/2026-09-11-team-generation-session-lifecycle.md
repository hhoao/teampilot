# Team Generation Session Lifecycle Implementation Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

Goal: Make generated Builder Sessions use normal first-prompt naming and add a persisted, default-off troubleshooting option that retains the Builder Session after handoff without changing the active Session.

Architecture: Extend TeamGenerationSettings and TeamGenerationSettingsSnapshot with retainBuilderSession, so each workflow stores an immutable cleanup policy in its existing Job settings snapshot. The coordinator applies originalPrompt as Builder metadata, while cleanup either follows the existing delete path or retains the Builder, revokes authorization, and archives the Job. Handoff selection remains unchanged.

Tech Stack: Dart, Flutter, flutter_bloc, filesystem-backed JSON settings, package:test through dart run tool/run_tests.dart.

## Global Constraints

- Never invoke flutter test directly; use cd client && dart run tool/run_tests.dart <paths/options>.
- Before claiming done, run cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart.
- Edit localization only in client/lib/l10n/app_en.arb and client/lib/l10n/app_zh.arb.
- Preserve unrelated dirty-worktree changes and commit only feature files.
- Retained Builder Sessions keep SessionPurpose.teamGeneration and must not retain Team Composer authorization.
- Use AppLogger for diagnostics and never print.
- Do not change session/team placement logic.

---

### Task 1: Persist Builder retention in settings and snapshots

Files:
- Modify: client/lib/models/team_generation_settings.dart
- Test: client/test/models/team_generation_settings_test.dart
- Test: client/test/services/team_generation/team_generation_settings_store_test.dart

Interfaces:
- Add TeamGenerationSettings.retainBuilderSession with default false.
- Add TeamGenerationSettingsSnapshot.retainBuilderSession with JSON, equality, and hash support.
- hydrateTeamGenerationSettings and resolveTeamGenerationSettingsSnapshot must preserve the field.
- Include the field in the snapshot revision canonical input.
- TeamGenerationJob already persists the complete settings snapshot; do not add a duplicate Job field.

- [ ] Step 1: Write failing tests.

Add model coverage asserting:
    expect(TeamGenerationSettings().retainBuilderSession, isFalse);
    expect(
      TeamGenerationSettings.fromJson({'retainBuilderSession': true})
          .retainBuilderSession,
      isTrue,
    );

Add snapshot coverage:
    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(retainBuilderSession: true),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    final reloaded =
        TeamGenerationSettingsSnapshot.fromJson(snapshot.toJson());
    expect(reloaded.retainBuilderSession, isTrue);
    expect(reloaded, snapshot);

Also build snapshots with true and false and assert their revisions differ. Add a store save/load test using TeamGenerationSettings(retainBuilderSession: true).

- [ ] Step 2: Run the red tests.

Run:
    cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart --plain-name "retains"

Expected: FAIL because the new fields do not exist.

- [ ] Step 3: Implement the model changes.

Add bool retainBuilderSession = false to both settings factories and private constructors. Decode it with json['retainBuilderSession'] == true, pass it through normalized() and hydrateTeamGenerationSettings(), and include it in equality/hash. Write the setting to JSON when true so old files remain compact and missing fields remain false.

Add the same field to TeamGenerationSettingsSnapshot. Include it in fromJson, toJson, equality, and hash. Add 'retainBuilderSession': normalizedSettings.retainBuilderSession to the canonical map used by resolveTeamGenerationSettingsSnapshot, and pass the value into the returned snapshot.

- [ ] Step 4: Run focused tests.

Run:
    cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart

Expected: PASS.

- [ ] Step 5: Commit.

    git add client/lib/models/team_generation_settings.dart client/test/models/team_generation_settings_test.dart client/test/services/team_generation/team_generation_settings_store_test.dart
    git commit -m "feat(team-generation): persist builder retention policy"

### Task 2: Add the troubleshooting switch to the generation settings dialog

Files:
- Modify: client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart
- Modify: client/lib/l10n/app_en.arb
- Modify: client/lib/l10n/app_zh.arb
- Test: client/test/services/team_generation/team_generation_settings_store_test.dart

Interfaces:
- The dialog state owns _retainBuilderSession and loads it from TeamGenerationSettingsStore.
- _save passes it to TeamGenerationSettings.
- The switch is off for missing/legacy settings and clearly describes troubleshooting behavior.

- [ ] Step 1: Add localized copy.

Add these matching keys to both ARB files:
English:
    teamGenerateRetainBuilderSession: Keep Builder Session for troubleshooting
    teamGenerateRetainBuilderSessionHint: When enabled, the generated team opens normally but the Builder Session is kept for inspecting the generation process.

Chinese:
    teamGenerateRetainBuilderSession: 保留团队构建 Session 以便排错
    teamGenerateRetainBuilderSessionHint: 开启后仍会正常打开生成的团队，但会保留构建 Session，方便查看团队生成过程。

Do not hand-edit generated localization Dart files.

- [ ] Step 2: Implement the dialog state and control.

Add bool _retainBuilderSession = false to _GenerateSettingsDialogState. In _loadInitial, assign settings.retainBuilderSession in the existing setState. Render the project’s existing setting-row style after the capability note and before the footer, with title l10n.teamGenerateRetainBuilderSession, hint l10n.teamGenerateRetainBuilderSessionHint, value _retainBuilderSession, and a callback that updates state. Disable the callback while loading.

In _save, pass retainBuilderSession: _retainBuilderSession to TeamGenerationSettings.

- [ ] Step 3: Run analyze and persistence tests.

Run:
    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
    cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart

Expected: analyze and tests pass.

- [ ] Step 4: Commit.

    git add client/lib/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb
    git commit -m "feat(team-generation): add builder retention troubleshooting switch"

### Task 3: Name Builder Sessions from the original prompt

Files:
- Modify: client/lib/services/launch/session_prompt_metadata_sync.dart
- Modify: client/lib/cubits/chat/session_launch_service.dart
- Modify: client/lib/cubits/chat_cubit.dart
- Modify: client/lib/services/team_generation/team_generation_session_port.dart
- Modify: client/lib/cubits/team/cubit_team_generation_session_port.dart
- Modify: all test fakes implementing TeamGenerationSessionPort under client/test/services/team_generation/
- Test: client/test/services/launch/session_prompt_metadata_sync_test.dart
- Test: client/test/services/team_generation/team_generation_coordinator_test.dart

Interfaces:
- Add Future<void> applyFirstPromptTitle(String sessionId, String firstPrompt) to TeamGenerationSessionPort.
- Add optional bool allowTeamGeneration = false to the existing metadata title path, preserving the default guard for automatic kickoff capture.
- The coordinator calls the port with originalPrompt immediately after createBuilder and treats title failure as non-fatal.

- [ ] Step 1: Write failing tests.

In session_prompt_metadata_sync_test.dart, add a team-generation session and assert that applyFirstPromptTitle(..., allowTeamGeneration: true) renames it to the first non-empty line, while the existing call without the flag still skips team-generation sessions.

In the coordinator fake, record title:<sessionId>:<prompt> and assert it appears after builder creation and before kickoff delivery. Add a fake title failure and assert coordinator.start still emits the kickoff delivery event.

- [ ] Step 2: Run the red tests.

Run:
    cd client && dart run tool/run_tests.dart test/services/launch/session_prompt_metadata_sync_test.dart test/services/team_generation/team_generation_coordinator_test.dart

Expected: FAIL because the optional argument, port method, and coordinator event do not exist.

- [ ] Step 3: Implement the opt-in metadata path.

Change SessionPromptMetadataSync.applyFirstPromptTitle to accept named allowTeamGeneration = false and pass it into _maybeAutoRenameFromFirstPrompt. Change the purpose guard to return only when session.purpose is teamGeneration and allowTeamGeneration is false. Thread the named argument through SessionLaunchService and ChatCubit, preserving false defaults.

Add applyFirstPromptTitle to TeamGenerationSessionPort. In CubitTeamGenerationSessionPort, delegate with allowTeamGeneration: true. Update every test fake with a no-op or recording implementation.

- [ ] Step 4: Apply originalPrompt in the coordinator.

After createBuilder and before select/waitForInputReady, add:
    try {
      await _sessionPort.applyFirstPromptTitle(
        builderSessionId,
        originalPrompt,
      );
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[team-generation] builder title update failed',
        error: error,
        stackTrace: stackTrace,
      );
    }

Import the existing logger utility. This changes metadata only; the CLI still receives buildTeamGenerationKickoff(originalPrompt).

- [ ] Step 5: Run tests and commit.

Run:
    cd client && dart run tool/run_tests.dart test/services/launch/session_prompt_metadata_sync_test.dart test/services/team_generation/team_generation_coordinator_test.dart

Expected: PASS.

    git add client/lib/services/launch/session_prompt_metadata_sync.dart client/lib/cubits/chat/session_launch_service.dart client/lib/cubits/chat_cubit.dart client/lib/services/team_generation/team_generation_session_port.dart client/lib/cubits/team/cubit_team_generation_session_port.dart client/test/services/launch/session_prompt_metadata_sync_test.dart client/test/services/team_generation
    git commit -m "feat(team-generation): name builder sessions from user prompts"

### Task 4: Retain Builder conditionally during cleanup

Files:
- Modify: client/lib/services/team_generation/team_generation_cleanup_service.dart
- Test: client/test/services/team_generation/team_generation_cleanup_service_test.dart

Interfaces:
- cleanup reads job.settings.retainBuilderSession.
- false keeps the existing prompt-delivery, flush, idle, delete, revoke, and compact path.
- true records builderRetained, skips idle waiting and deletion, revokes the token, and compacts the Job to complete.

- [ ] Step 1: Write the failing test.

Extend seedJob with bool retainBuilderSession = false and pass it into TeamGenerationSettings. Add a test with both existing successful gate receipts and retainBuilderSession: true. Assert cleanup returns cleaned, deletedSessions is empty, revoke receives wf, Job phase is complete, and builderRetained is a succeeded receipt. Configure the fake activity stream to throw if subscribed, proving idle waiting is skipped.

- [ ] Step 2: Run the red test.

Run:
    cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_cleanup_service_test.dart --plain-name "retention mode keeps Builder"

Expected: FAIL because the current service waits for idle and deletes Builder.

- [ ] Step 3: Implement the retention branch.

After prompt-delivery and finalize-response gates, before the builder-idle gate, mutate the Job to cleaning and add:
    if (job.settings.retainBuilderSession) {
      await _jobStore.mutate(workspaceId, workflowId, (current) {
        return current.copyWith(
          phase: _safeAdvance(current.phase),
          receipts: {
            ...current.receipts,
            'builderRetained': const TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
            ),
          },
        );
      });
      _revokeToken(workflowId);
      await _jobStore.compactComplete(workspaceId, workflowId);
      return TeamGenerationCleanupResult.cleaned;
    }

Keep the existing default branch and identity checks unchanged. The stable builderRetained receipt makes the retention side effect idempotent before compactComplete.

- [ ] Step 4: Run all cleanup tests and commit.

Run:
    cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_cleanup_service_test.dart

Expected: PASS for default deletion and retention.

    git add client/lib/services/team_generation/team_generation_cleanup_service.dart client/test/services/team_generation/team_generation_cleanup_service_test.dart
    git commit -m "feat(team-generation): optionally retain builder session"

### Task 5: Verify handoff and recovery behavior

Files:
- Modify: client/test/services/team_generation/team_generation_coordinator_test.dart
- Modify: client/test/services/team_generation/team_generation_recovery_service_test.dart
- Modify: client/test/services/team_generation/team_generation_handoff_service_test.dart only if required for selection assertions
- Modify: client/lib/services/team_generation/team_generation_recovery_service.dart only if persisted snapshot policy is not forwarded

Interfaces:
- Handoff must select destinationSessionId before prompt delivery in both modes.
- Recovery must use job.settings.retainBuilderSession, not current global settings.
- Existing safety retention for ambiguous finalize responses remains unchanged.

- [ ] Step 1: Add retention-flow regression coverage.

Run the successful coordinator scenario with retainBuilderSession: true and assert destination selection precedes destination history delivery and no builderDeleted event occurs. Use the real cleanup service so this verifies the Job snapshot end-to-end.

- [ ] Step 2: Add recovery snapshot coverage.

Seed a Job with retainBuilderSession: true, successful profile/destination/finalize receipts, and global settings left false. Assert recovery forwards the seeded Job with retention enabled. Seed a false Job and assert the existing delete path. If recovery already forwards cleanup jobs directly, keep production code unchanged and retain the test.

- [ ] Step 3: Run the focused generation suite.

Run:
    cd client && dart run tool/run_tests.dart test/services/team_generation/team_generation_coordinator_test.dart test/services/team_generation/team_generation_handoff_service_test.dart test/services/team_generation/team_generation_recovery_service_test.dart test/services/team_generation/team_generation_cleanup_service_test.dart

Expected: PASS.

- [ ] Step 4: Commit only actual changes.

    git add client/test/services/team_generation/team_generation_coordinator_test.dart client/test/services/team_generation/team_generation_recovery_service_test.dart client/test/services/team_generation/team_generation_handoff_service_test.dart client/lib/services/team_generation/team_generation_recovery_service.dart
    git commit -m "test(team-generation): cover retained builder handoff and recovery"

Do not include team_generation_recovery_service.dart if it was not modified.

### Task 6: Verify the complete feature

- [ ] Step 1: Run fast verification.

    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
    cd client && dart run tool/run_tests.dart test/models/team_generation_settings_test.dart test/services/team_generation/team_generation_settings_store_test.dart test/services/launch/session_prompt_metadata_sync_test.dart test/services/team_generation/team_generation_coordinator_test.dart test/services/team_generation/team_generation_cleanup_service_test.dart test/services/team_generation/team_generation_recovery_service_test.dart

- [ ] Step 2: Check the feature diff.

    git status --short
    git diff --check HEAD~5

Confirm no unrelated pre-existing modifications, generated localization Dart files, client/google_fonts/, or vendored package changes were added.

- [ ] Step 3: Run required full verification once.

    cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart

Expected: exit code 0. Capture any unrelated failure exactly before changing scope.

- [ ] Step 4: Request code review using the requesting-code-review skill after verification. Review default false behavior, old JSON compatibility, originalPrompt title source, destination selection, token revocation, and protection against deleting the destination Session.

- [ ] Step 5: Final report must include the debug switch behavior, title behavior, active Session result, and exact passing commands.
