import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/landing_launch_context.dart';
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
    'resolveLandingDraft creates a personal draft with no persisted policy',
    () async {
      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        storage: fakeHomeStorage(),
        store: LandingPrefsStore(
          fs: InMemoryFilesystem(),
          pathOverride: '/prefs.json',
          storage: fakeHomeStorage(),
        ),
      );
      expect(draft.isPersonal, isTrue);
    },
  );

  test(
    'resolveLandingDraft leaves custom launch unset when no prefs',
    () async {
      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        storage: fakeHomeStorage(),
        store: LandingPrefsStore(
          fs: InMemoryFilesystem(),
          pathOverride: '/prefs.json',
          storage: fakeHomeStorage(),
        ),
      );
      expect(draft.cli, isNull);
    },
  );

  test('resolveLandingDraft prefers persisted preferences', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(),
    );
    await persistLandingDraft(
      workspace.workspaceId,
      const LandingLaunchContext(isPersonal: true, teamId: 'team-1'),
      storage: fakeHomeStorage(),
      store: store,
    );

    final draft = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      storage: fakeHomeStorage(),
      store: store,
    );
    expect(draft.teamId, 'team-1');
  });

  test('persistLandingDraft omits launch security policy', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(),
    );
    const draft = LandingLaunchContext(isPersonal: true);

    await persistLandingDraft(
      workspace.workspaceId,
      draft,
      storage: fakeHomeStorage(),
      store: store,
    );

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      storage: fakeHomeStorage(),
      store: store,
    );
    expect(resolved.isPersonal, isTrue);
  });

  test('persistLandingDraft round-trips the team selection', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(),
    );
    const draft = LandingLaunchContext(isPersonal: false, teamId: 'team-1');

    await persistLandingDraft(
      workspace.workspaceId,
      draft,
      storage: fakeHomeStorage(),
      store: store,
    );

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      storage: fakeHomeStorage(),
      store: store,
    );
    expect(resolved.teamId, 'team-1');
  });

  test(
    'persistLandingDraft round-trips generate launch in team mode',
    () async {
      final store = LandingPrefsStore(
        fs: InMemoryFilesystem(),
        pathOverride: '/prefs.json',
        storage: fakeHomeStorage(),
      );
      const draft = LandingLaunchContext(
        isPersonal: false,
        generateLaunch: true,
        teamId: 'last-team',
      );

      await persistLandingDraft(
        workspace.workspaceId,
        draft,
        storage: fakeHomeStorage(),
        store: store,
      );

      final resolved = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        storage: fakeHomeStorage(),
        store: store,
      );
      expect(resolved.generateLaunch, isTrue);
      expect(resolved.teamId, 'last-team');
    },
  );

  test('persistLandingDraft round-trips custom four-tuple', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(),
    );
    const draft = LandingLaunchContext(
      isPersonal: true,
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt-4',
      effort: 'high',
    );

    await persistLandingDraft(
      workspace.workspaceId,
      draft,
      storage: fakeHomeStorage(),
      store: store,
    );

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      storage: fakeHomeStorage(),
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
    final store = LandingPrefsStore(
      fs: fs,
      pathOverride: '/prefs.json',
      storage: fakeHomeStorage(),
    );
    await persistLandingDraft(
      workspace.workspaceId,
      const LandingLaunchContext(isPersonal: true),
      storage: fakeHomeStorage(),
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

    test('empty draft leaves provider unset for CLI-side resolution', () {
      final identity = resolveLandingSimpleLaunchIdentity(
        presets: const [],
        expertKey: 'expert/c',
      );

      expect(identity.cli, CliTool.claude);
      // No default official provider ids: the launch flow resolves the
      // provider from the live catalog when none is pinned.
      expect(identity.provider, isEmpty);
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

    test('following identity takes live preset provider and model', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'cursor-composer',
        provider: 'old-account',
        model: 'old-model',
        effort: 'low',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'cursor-account');
      expect(enriched.model, 'composer-2.5');
      expect(enriched.effort, '');
      expect(enriched.cli, CliTool.cursor);
      expect(enriched.presetId, 'cursor-composer');
    });

    test('missing preset keeps pinned provider and model', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        presetId: 'gone',
        provider: 'old-account',
        model: 'old-model',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'old-account');
      expect(enriched.model, 'old-model');
      expect(enriched.presetId, 'gone');
    });

    test('preset CLI mismatch keeps pinned launch fields', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.codex,
        presetId: 'cursor-composer',
        provider: 'openai',
        model: 'gpt',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.cli, CliTool.codex);
      expect(enriched.provider, 'openai');
      expect(enriched.model, 'gpt');
    });

    test('empty presetId does not expand', () {
      const identity = SimpleLaunchIdentity(
        cli: CliTool.cursor,
        provider: 'pinned',
        model: 'pinned-m',
      );

      final enriched = enrichSimpleLaunchIdentityFromPreset(
        identity: identity,
        presets: presets,
      );

      expect(enriched.provider, 'pinned');
      expect(enriched.model, 'pinned-m');
    });
  });
}
