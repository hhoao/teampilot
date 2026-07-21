import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_continue_overrides_controller.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/config_bundle.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/session_review_compose_card.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/preset_resolver.dart';
import 'package:teampilot/services/session/session_continue_overrides_apply.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';
import 'package:teampilot/widgets/compose/compose_permission_chip.dart';

import '../../support/post_frame_test_harness.dart';

/// Acceptance coverage for session history continue chrome (design §Acceptance).
void main() {
  const controller = SessionContinueOverridesController();

  CliPreset claudePreset({
    String id = 'preset-b',
    String provider = 'openai',
    String model = 'gpt-4o',
    String effort = 'medium',
  }) {
    return CliPreset(
      id: id,
      name: 'Beta',
      cli: CliTool.claude,
      provider: provider,
      model: model,
      effort: effort,
      createdAt: 0,
      updatedAt: 0,
    );
  }

  AppSession simpleSession() {
    return AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/w')],
      cli: CliTool.claude,
      provider: 'anthropic',
      model: 'claude-sonnet',
      effort: 'high',
      presetId: 'preset-a',
      createdAt: 1,
      updatedAt: 1,
    );
  }

  group('acceptance: continue chrome', () {
    test(
      '1. Simple preset change persists and merge sees new provider/model',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'continue_chrome_simple_',
        );
        addTearDown(() => tmp.deleteSync(recursive: true));
        final repo = SessionRepository(rootDir: tmp.path);
        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/w'),
        ]);
        final created = await repo.createSession(
          workspace.workspaceId,
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          effort: 'high',
          presetId: 'preset-a',
        );

        final patched = controller.patchPreset(
          session: created,
          preset: claudePreset(),
          lockedCli: CliTool.claude,
        );
        expect(patched, isNotNull);
        await controller.persistPreset(repo: repo, patched: patched!);

        final disk = (await repo.loadSessions()).single;
        expect(disk.presetId, 'preset-b');
        expect(disk.provider, 'openai');
        expect(disk.model, 'gpt-4o');

        // Simple connect: identity → plan.member → finalize overrides.
        const packMember = TeamMemberConfig(
          id: 's1',
          name: 'Simple',
          cli: CliTool.codex,
          provider: 'pack-provider',
          model: 'pack-model',
        );
        final base = disk.simpleIdentity.applyToMember(packMember);
        final merged = applySessionContinueOverrides(
          baseMember: base,
          session: disk,
          memberId: disk.sessionId,
          isSimple: true,
        );

        expect(merged.cli, CliTool.claude);
        expect(merged.provider, 'openai');
        expect(merged.model, 'gpt-4o');
        expect(merged.effort, 'medium');
      },
    );

    test('2. Team member override does not mutate team template', () {
      const templateMember = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'template-provider',
        model: 'template-model',
        dangerouslySkipPermissions: true,
      );
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        members: const [templateMember],
      );
      final session = simpleSession().copyWith(
        sessionTeam: 'team-1',
        members: const [],
      );

      final patched = controller.patchPreset(
        session: session,
        preset: claudePreset(),
        memberId: 'builder-0',
        lockedCli: CliTool.claude,
      );
      expect(patched, isNotNull);

      // Template object identity + fields unchanged.
      expect(identical(team.members.single, templateMember), isTrue);
      expect(team.members.single.provider, 'template-provider');
      expect(team.members.single.model, 'template-model');
      expect(
        patched!.continueOverrides.memberOverrides['builder-0']?.provider,
        'openai',
      );

      final merged = applySessionContinueOverrides(
        baseMember: templateMember,
        session: patched,
        memberId: 'builder-0',
        isSimple: false,
      );
      expect(merged.provider, 'openai');
      expect(merged.model, 'gpt-4o');
      expect(templateMember.provider, 'template-provider');
    });

    test('3. Permission full access → effective skip true on merge', () {
      final session = controller.patchPermission(
        session: simpleSession().copyWith(sessionTeam: 'team-1'),
        dangerouslySkipPermissions: true,
        memberId: 'builder-0',
      );
      const base = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        dangerouslySkipPermissions: false,
      );

      final merged = applySessionContinueOverrides(
        baseMember: base,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
      );
      expect(merged.dangerouslySkipPermissions, isTrue);
      expect(
        resolveContinueSkipPermissions(
          sessionLevel: session.continueOverrides.dangerouslySkipPermissions,
          memberLevel: session
              .continueOverrides
              .memberOverrides['builder-0']
              ?.dangerouslySkipPermissions,
          launchDefault: base.dangerouslySkipPermissions,
        ),
        isTrue,
      );
    });

    test('4. Cross-CLI preset rejected (no write)', () async {
      final tmp = await Directory.systemTemp.createTemp(
        'continue_chrome_xcli_',
      );
      addTearDown(() => tmp.deleteSync(recursive: true));
      final repo = SessionRepository(rootDir: tmp.path);
      final workspace = await repo.createWorkspace([
        const WorkspaceFolder(path: '/w'),
      ]);
      final created = await repo.createSession(
        workspace.workspaceId,
        cli: CliTool.claude,
        presetId: 'preset-a',
        provider: 'anthropic',
        model: 'claude-sonnet',
      );

      final patched = controller.patchPreset(
        session: created,
        preset: claudePreset().copyWith(cli: CliTool.codex),
        lockedCli: CliTool.claude,
      );
      expect(patched, isNull);

      final disk = (await repo.loadSessions()).single;
      expect(disk.presetId, 'preset-a');
      expect(disk.provider, 'anthropic');
      expect(disk.model, 'claude-sonnet');
    });

    test(
      '4b. Team lockedCli prefers binding.cli over live Cursor profile',
      () {
        final liveTeam = TeamProfile(
          id: 't1',
          name: 'Team',
          cli: CliTool.cursor,
          members: [
            TeamMemberConfig(
              id: 'team-lead',
              name: 'Lead',
              cli: CliTool.cursor,
            ),
          ],
        );
        final session = AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          sessionTeam: 't1',
          members: [
            SessionMemberBinding(
              rosterMemberId: 'team-lead',
              taskId: 'task',
              cli: CliTool.claude,
            ),
          ],
          createdAt: 1,
        );
        final lockedCli = sessionMemberLaunchCli(
          session: session,
          team: liveTeam,
          member: liveTeam.members.first,
        );
        expect(lockedCli, CliTool.claude);

        final presets = [
          claudePreset(id: 'claude-p'),
          claudePreset(id: 'cursor-p').copyWith(cli: CliTool.cursor),
        ];
        expect(
          presetsForCli(presets, lockedCli).map((p) => p.id),
          ['claude-p'],
        );
      },
    );

    test(
      '5. Landing session-level permission → unedited team member uses '
      'session default (not template)',
      () {
        // Landing writes session-level only; no memberOverrides fan-out.
        final session = AppSession(
          sessionId: 's1',
          workspaceId: 'w1',
          sessionTeam: 'team-1',
          createdAt: 1,
          continueOverrides: const SessionContinueOverrides(
            dangerouslySkipPermissions: true,
          ),
        );
        const templateMember = TeamMemberConfig(
          id: 'builder-0',
          name: 'Builder',
          cli: CliTool.claude,
          // Template often skips; session-level must still win when set.
          dangerouslySkipPermissions: false,
        );

        final merged = applySessionContinueOverrides(
          baseMember: templateMember,
          session: session,
          memberId: 'builder-0',
          isSimple: false,
        );
        expect(merged.dangerouslySkipPermissions, isTrue);
        expect(session.continueOverrides.memberOverrides, isEmpty);
        expect(templateMember.dangerouslySkipPermissions, isFalse);
      },
    );

    test('6. Member switch uses that member’s override map entry', () {
      final session = AppSession(
        sessionId: 's1',
        workspaceId: 'w1',
        sessionTeam: 'team-1',
        createdAt: 1,
        continueOverrides: const SessionContinueOverrides(
          dangerouslySkipPermissions: false,
          memberOverrides: {
            'builder-0': SessionMemberContinueOverride(
              presetId: 'preset-builder',
              provider: 'openai',
              model: 'gpt-4o',
              dangerouslySkipPermissions: true,
            ),
            'reviewer-0': SessionMemberContinueOverride(
              presetId: 'preset-reviewer',
              provider: 'anthropic',
              model: 'claude-opus',
              dangerouslySkipPermissions: false,
            ),
          },
        ),
      );
      const builder = TeamMemberConfig(
        id: 'builder-0',
        name: 'Builder',
        cli: CliTool.claude,
        provider: 'template',
        model: 'template-m',
        dangerouslySkipPermissions: true,
      );
      const reviewer = TeamMemberConfig(
        id: 'reviewer-0',
        name: 'Reviewer',
        cli: CliTool.claude,
        provider: 'template',
        model: 'template-m',
        dangerouslySkipPermissions: true,
      );

      final builderMerged = applySessionContinueOverrides(
        baseMember: builder,
        session: session,
        memberId: 'builder-0',
        isSimple: false,
      );
      final reviewerMerged = applySessionContinueOverrides(
        baseMember: reviewer,
        session: session,
        memberId: 'reviewer-0',
        isSimple: false,
      );

      expect(builderMerged.provider, 'openai');
      expect(builderMerged.model, 'gpt-4o');
      expect(builderMerged.dangerouslySkipPermissions, isTrue);

      expect(reviewerMerged.provider, 'anthropic');
      expect(reviewerMerged.model, 'claude-opus');
      expect(reviewerMerged.dangerouslySkipPermissions, isFalse);

      // Chip selection ids follow the selected member's override entry.
      expect(
        session.continueOverrides.memberOverrides['builder-0']?.presetId,
        'preset-builder',
      );
      expect(
        session.continueOverrides.memberOverrides['reviewer-0']?.presetId,
        'preset-reviewer',
      );
    });
  });

  group('acceptance: cubit persist path', () {
    setUp(setUpTestAppStorage);
    tearDown(tearDownTestAppStorage);

    test(
      'ChatCubit Simple preset + permission round-trip feeds merge',
      () async {
        final tmp = await Directory.systemTemp.createTemp(
          'continue_chrome_cubit_',
        );
        addTearDown(() async => deleteTempDirBestEffort(tmp));
        final repo = SessionRepository(rootDir: tmp.path);
        final cubit = ChatCubit(
          executableResolver: () => 'true',
          automationRepository: testAutomationRepository(),
          sessionRepository: repo,
        );
        addTearDown(cubit.close);

        final workspace = await repo.createWorkspace([
          const WorkspaceFolder(path: '/w'),
        ]);
        final session = await repo.createSession(
          workspace.workspaceId,
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet',
          presetId: 'preset-a',
        );
        await cubit.loadWorkspaceData(repo);

        expect(
          await cubit.setSessionContinuePreset(
            sessionId: session.sessionId,
            preset: claudePreset(),
            lockedCli: CliTool.claude,
          ),
          isTrue,
        );
        expect(
          await cubit.setSessionContinuePermission(
            sessionId: session.sessionId,
            dangerouslySkipPermissions: true,
          ),
          isTrue,
        );

        final live = cubit.state.sessions.single;
        const packMember = TeamMemberConfig(
          id: 'x',
          name: 'Simple',
          cli: CliTool.claude,
        );
        final merged = applySessionContinueOverrides(
          baseMember: live.simpleIdentity.applyToMember(packMember),
          session: live,
          memberId: live.sessionId,
          isSimple: true,
        );
        expect(merged.provider, 'openai');
        expect(merged.model, 'gpt-4o');
        expect(merged.dangerouslySkipPermissions, isTrue);
      },
    );
  });

  group('acceptance: continue chrome widgets', () {
    testWidgets(
      'SessionReviewComposeCard shows continue chips; no project/mode chrome',
      (tester) async {
        final textController = TextEditingController();
        final focusNode = FocusNode();
        addTearDown(textController.dispose);
        addTearDown(focusNode.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SessionReviewComposeCard(
                controller: textController,
                focusNode: focusNode,
                hint: 'Continue',
                canSubmit: false,
                onSubmit: () {},
                onChanged: (_) {},
                attachTooltip: 'Attach',
                enhanceTooltip: 'Enhance',
                voiceTooltip: 'Voice',
                voiceCancelTooltip: 'Cancel',
                voiceStopTooltip: 'Stop',
                isEnhancing: false,
                isVoiceListening: false,
                voiceElapsed: Duration.zero,
                voiceSoundLevel: 0,
                onAttach: () {},
                onEnhance: () {},
                onVoice: () {},
                onVoiceCancel: () {},
                onVoiceStop: () {},
                workspaceRoot: '/tmp',
                skills: const [],
                plugins: const [],
                slashBundle: const ConfigBundle(),
                identityLabel: 'My Team',
                sameCliPresets: [claudePreset()],
                selectedPresetId: 'preset-b',
                modelPresetLabel: 'Beta',
                emptyPresetHintLabel: 'No presets',
                onPresetSelected: (_) {},
                dangerouslySkipPermissions: false,
                defaultPermissionsLabel: 'Default',
                fullAccessPermissionsLabel: 'Full access',
                onPermissionSelected: (_) {},
              ),
            ),
          ),
        );

        expect(find.byType(ComposeModelPresetChip), findsOneWidget);
        expect(find.byType(ComposePermissionChip), findsOneWidget);
        expect(find.text('My Team'), findsOneWidget);
        expect(find.text('Beta'), findsOneWidget);
        expect(find.text('Default'), findsOneWidget);

        // Landing session-fixed chrome must stay absent on review compose.
        expect(find.text('Project'), findsNothing);
        expect(find.text('Worktree'), findsNothing);
        expect(find.text('Simple'), findsNothing);
        expect(find.text('Team'), findsNothing);
        expect(find.textContaining('Mode'), findsNothing);
      },
    );
  });
}
