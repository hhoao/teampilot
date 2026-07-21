import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/session_continue_overrides.dart';
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

  test('resolveLandingDraft defaults dangerouslySkipPermissions to true', () async {
    final draft = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      store: LandingPrefsStore(fs: InMemoryFilesystem(), pathOverride: '/prefs.json'),
    );
    expect(draft.dangerouslySkipPermissions, isTrue);
  });

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
      expect(draft.dangerouslySkipPermissions, isFalse);
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
          dangerouslySkipPermissions: true,
        ),
        store: store,
      );

      final draft = await resolveLandingDraft(
        workspaceId: workspace.workspaceId,
        store: store,
        simpleModeDefaultFullAccess: false,
      );
      expect(draft.dangerouslySkipPermissions, isTrue);
    },
  );

  test('persistLandingDraft round-trips dangerouslySkipPermissions false', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
    );
    const draft = LandingLaunchContext(
      isPersonal: true,
      dangerouslySkipPermissions: false,
    );

    await persistLandingDraft(workspace.workspaceId, draft, store: store);

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      store: store,
    );
    expect(resolved.dangerouslySkipPermissions, isFalse);
  });

  test('persistLandingDraft round-trips dangerouslySkipPermissions true', () async {
    final store = LandingPrefsStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/prefs.json',
    );
    const draft = LandingLaunchContext(
      isPersonal: true,
      dangerouslySkipPermissions: true,
    );

    await persistLandingDraft(workspace.workspaceId, draft, store: store);

    final resolved = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      store: store,
    );
    expect(resolved.dangerouslySkipPermissions, isTrue);
  });

  test('landing draft maps to session continue overrides for create', () {
    const draft = LandingLaunchContext(
      isPersonal: true,
      dangerouslySkipPermissions: true,
    );
    final overrides = SessionContinueOverrides(
      dangerouslySkipPermissions: draft.dangerouslySkipPermissions,
    );
    expect(overrides.dangerouslySkipPermissions, isTrue);
  });
}
