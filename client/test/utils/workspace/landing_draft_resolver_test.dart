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

  test('resolveLandingDraft defaults dangerouslySkipPermissions to false', () async {
    final draft = await resolveLandingDraft(
      workspaceId: workspace.workspaceId,
      store: LandingPrefsStore(fs: InMemoryFilesystem(), pathOverride: '/prefs.json'),
    );
    expect(draft.dangerouslySkipPermissions, isFalse);
  });

  test('persistLandingDraft round-trips dangerouslySkipPermissions', () async {
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
