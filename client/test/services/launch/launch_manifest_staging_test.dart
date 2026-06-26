import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/personal_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/launch/manifest_executor.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('stageSessionLaunch records manifest entries on local target', () async {
    final lifecycle = SessionLifecycleService(
      appDataBasePath: AppStorage.paths.basePath,
    );
    final roots = await lifecycle.resolveWorkContextForTargetId('local');
    final svc = await lifecycle.configProfileServiceFor(roots);
    final staged = await svc.stageSessionLaunch(
      readDelegate: roots.fs,
      workTeampilotRoot: roots.appDataRoot,
      workspaceId: 'ws1',
      sessionId: 'sess1',
      profileId: 'personal-default',
      personal: const PersonalProfile(id: 'p1', display: 'p1'),
    );
    expect(staged.manifest.files, isNotEmpty);

    await const ManifestExecutor().flush(
      manifest: staged.manifest,
      targetFs: roots.fs,
      sourceFs: roots.fs,
    );
  });

  test('stageTeamLaunch records manifest entries on local target', () async {
    final lifecycle = SessionLifecycleService(
      appDataBasePath: AppStorage.paths.basePath,
    );
    final roots = await lifecycle.resolveWorkContextForTargetId('local');
    final svc = await lifecycle.configProfileServiceFor(roots);
    const sessionId = '00000000-0000-4000-8000-000000000099';
    final staged = await svc.stageTeamLaunch(
      readDelegate: roots.fs,
      workTeampilotRoot: roots.appDataRoot,
      workspaceId: 'ws1',
      sessionId: sessionId,
      teamId: 'team-a',
      cliTeamName: sessionId,
      cli: CliTool.claude,
      members: const [
        TeamMemberConfig(id: 'builder', name: 'builder'),
      ],
      member: const TeamMemberConfig(id: 'builder', name: 'builder'),
      team: const TeamProfile(
        id: 'team-a',
        name: 'team-a',
        cli: CliTool.claude,
      ),
    );
    expect(staged.manifest.entries, isNotEmpty);

    await const ManifestExecutor().flush(
      manifest: staged.manifest,
      targetFs: roots.fs,
      sourceFs: roots.fs,
    );
  });
}
