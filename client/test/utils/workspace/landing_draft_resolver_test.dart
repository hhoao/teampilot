import 'package:teampilot/models/launch_security_policy.dart';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/home_workspace/landing_prefs_store.dart';
import 'package:teampilot/utils/workspace/landing_draft_resolver.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  final workspace = Workspace(
    workspaceId: 'ws-a',
    display: 'Test',
    folders: const [WorkspaceFolder(path: '/projects/app')],
    createdAt: 0,
    updatedAt: 0,
  );

  test(
    'resolveLandingDraft defaults to full access for landing compatibility',
    () async {
      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: LandingPrefsStore(
          fs: InMemoryFilesystem(),
          pathOverride: '/prefs.json',
        ),
      );
      expect(draft.launchSecurityPolicy.requiresDangerousExecution, isTrue);
    },
  );

  test(
    'resolveLandingDraft uses simpleModeDefaultFullAccess when no prefs',
    () async {
      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: LandingPrefsStore(
          fs: InMemoryFilesystem(),
          pathOverride: '/prefs.json',
        ),
        simpleModeDefaultFullAccess: false,
      );
      expect(draft.launchSecurityPolicy.requiresDangerousExecution, isFalse);
    },
  );

  test(
    'resolveLandingDraft prefers persisted prefs over simpleModeDefaultFullAccess',
    () async {
      final store = LandingPrefsStore(
        fs: InMemoryFilesystem(),
        pathOverride: '/prefs.json',
      );
      await persistLandingDraft(
        workspace.workspaceId,
        const LandingLaunchContext(
          isPersonal: true,
          launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
        ),
        store: store,
      );

      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: store,
        simpleModeDefaultFullAccess: false,
      );
      expect(draft.launchSecurityPolicy.requiresDangerousExecution, isTrue);
    },
  );

  test(
    'persistLandingDraft round-trips a safe launch security policy',
    () async {
      final store = LandingPrefsStore(
        fs: InMemoryFilesystem(),
        pathOverride: '/prefs.json',
      );
      const draft = LandingLaunchContext(
        isPersonal: true,
        launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      );

      await persistLandingDraft(workspace.workspaceId, draft, store: store);

      final resolved = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: store,
      );
      expect(resolved.launchSecurityPolicy.requiresDangerousExecution, isFalse);
    },
  );

  test(
    'persistLandingDraft round-trips a full-access launch security policy',
    () async {
      final store = LandingPrefsStore(
        fs: InMemoryFilesystem(),
        pathOverride: '/prefs.json',
      );
      const draft = LandingLaunchContext(
        isPersonal: true,
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
      );

      await persistLandingDraft(workspace.workspaceId, draft, store: store);

      final resolved = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: store,
      );
      expect(resolved.launchSecurityPolicy.requiresDangerousExecution, isTrue);
    },
  );

  test('persistLandingDraft round-trips custom four-tuple', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
    );
    const draft = LandingLaunchContext(
      isPersonal: true,
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt-4',
      effort: 'high',
    );

    await persistLandingDraft(workspace.workspaceId, draft, store: store);

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      store: store,
    );
    expect(resolved.cli, CliTool.cursor);
    expect(resolved.provider, 'cursor-account');
    expect(resolved.model, 'gpt-4');
    expect(resolved.effort, 'high');
    expect(resolved.presetId, isNull);
  });

  test('persistLandingDraft omits empty custom fields from JSON', () async {
    final fs = InMemoryFilesystem();
    final store = LandingPrefsStore(fs: fs, pathOverride: '/prefs.json');
    await persistLandingDraft(
      workspace.workspaceId,
      const LandingLaunchContext(isPersonal: true),
      store: store,
    );

    final text = fs.files['/prefs.json']!;
    final root = (jsonDecode(text) as Map).cast<String, Object?>();
    final wsPrefs = (root[workspace.workspaceId] as Map)
        .cast<String, Object?>();
    expect(wsPrefs.containsKey('cli'), isFalse);
    expect(wsPrefs.containsKey('provider'), isFalse);
    expect(wsPrefs.containsKey('model'), isFalse);
    expect(wsPrefs.containsKey('effort'), isFalse);
  });

  test('landing draft maps to session continue overrides for create', () {
    const draft = LandingLaunchContext(
      isPersonal: true,
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    );
    final overrides = SessionContinueOverrides(
      launchSecurityPolicy: LaunchSecurityPolicyOverride.fromPolicy(
        draft.launchSecurityPolicy,
      ),
    );
    expect(overrides.launchSecurityPolicy?.requiresDangerousExecution, isTrue);
  });

  group('resolveLandingSimpleLaunchIdentity', () {
    const preset = CliPreset(
      id: 'preset-1',
      name: 'Cursor Fast',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt-5.5',
      effort: 'high',
      createdAt: 1,
      updatedAt: 2,
    );

    test('uses preset only when presetId matches', () {
      final identity = resolveLandingSimpleLaunchIdentity(
        presets: const [preset],
        presetId: 'preset-1',
        cli: CliTool.claude,
        provider: 'claude-official',
        model: 'opus',
        effort: 'low',
        expertKey: 'expert/a',
      );

      expect(identity.cli, CliTool.cursor);
      expect(identity.provider, 'cursor-account');
      expect(identity.model, 'gpt-5.5');
      expect(identity.effort, 'high');
      expect(identity.presetId, 'preset-1');
      expect(identity.expertKey, 'expert/a');
    });

    test('uses custom four-tuple when preset missing', () {
      final identity = resolveLandingSimpleLaunchIdentity(
        presets: const [preset],
        presetId: null,
        cli: CliTool.codex,
        provider: 'openai-official',
        model: 'o3',
        effort: 'medium',
        expertKey: 'expert/b',
      );

      expect(identity.cli, CliTool.codex);
      expect(identity.provider, 'openai-official');
      expect(identity.model, 'o3');
      expect(identity.effort, 'medium');
      expect(identity.presetId, isEmpty);
      expect(identity.expertKey, 'expert/b');
    });

    test('empty draft falls back to Claude official provider', () {
      final identity = resolveLandingSimpleLaunchIdentity(
        presets: const [],
        expertKey: 'expert/c',
      );

      expect(identity.cli, CliTool.claude);
      expect(identity.provider, 'claude-official');
      expect(identity.presetId, isEmpty);
      expect(identity.expertKey, 'expert/c');
    });
  });

  group('seedLandingDraftPresetDefault', () {
    const preset = CliPreset(
      id: 'preset-1',
      name: 'Cursor Fast',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt-5.5',
      effort: 'high',
      createdAt: 1,
      updatedAt: 2,
    );

    test('seeds first preset for empty personal draft', () {
      const draft = LandingLaunchContext(isPersonal: true);
      final seeded = seedLandingDraftPresetDefault(draft, const [preset]);
      expect(seeded.presetId, 'preset-1');
      expect(seeded.cli, isNull);
    });

    test('keeps existing presetId', () {
      const draft = LandingLaunchContext(
        isPersonal: true,
        presetId: 'preset-1',
      );
      expect(seedLandingDraftPresetDefault(draft, const [preset]), draft);
    });

    test('keeps custom launch without preset', () {
      const draft = LandingLaunchContext(
        isPersonal: true,
        cli: CliTool.codex,
        provider: 'openai-official',
      );
      expect(seedLandingDraftPresetDefault(draft, const [preset]), draft);
    });

    test('no-op when presets empty', () {
      const draft = LandingLaunchContext(isPersonal: true);
      expect(seedLandingDraftPresetDefault(draft, const []), draft);
    });

    test('no-op for team draft', () {
      const draft = LandingLaunchContext(isPersonal: false, teamId: 'team-1');
      expect(seedLandingDraftPresetDefault(draft, const [preset]), draft);
    });
  });

  group('landing draft select helpers', () {
    test('selecting preset clears custom four-tuple', () {
      const base = LandingLaunchContext(
        isPersonal: true,
        cli: CliTool.cursor,
        provider: 'cursor-account',
        model: 'gpt',
        effort: 'high',
      );

      final next = landingDraftSelectingPreset(base, 'preset-1');

      expect(next.presetId, 'preset-1');
      expect(next.cli, isNull);
      expect(next.provider, isNull);
      expect(next.model, isNull);
      expect(next.effort, isNull);
    });

    test('selecting custom clears presetId', () {
      const base = LandingLaunchContext(isPersonal: true, presetId: 'preset-1');

      final next = landingDraftSelectingCustom(
        base,
        cli: CliTool.codex,
        provider: 'openai-official',
        model: 'o3',
        effort: 'medium',
      );

      expect(next.presetId, isNull);
      expect(next.cli, CliTool.codex);
      expect(next.provider, 'openai-official');
      expect(next.model, 'o3');
      expect(next.effort, 'medium');
    });
  });

  group('enrichSimpleLaunchIdentityFromPreset', () {
    const presets = [
      CliPreset(
        id: 'cursor-composer',
        name: 'Composer 2.5',
        cli: CliTool.cursor,
        provider: 'cursor-account',
        model: 'composer-2.5',
        createdAt: 1,
        updatedAt: 2,
      ),
    ];

    test('expands presetId-only identity into model and provider', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'cursor-composer',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.model, 'composer-2.5');
      expect(enriched.provider, 'cursor-account');
      expect(enriched.presetId, 'cursor-composer');
    });

    test('keeps session-pinned provider and model when already set', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'cursor-composer',
        provider: 'custom-provider',
        model: 'gpt-5.2',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.model, 'gpt-5.2');
      expect(enriched.provider, 'custom-provider');
    });
  });
}
