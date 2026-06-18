import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory tmp;
  late SessionRepository sessionRepo;
  late LaunchProfileRepository identityRepo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('session_data_personal_');
    final paths = AppPaths(tmp.path);
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    sessionRepo = SessionRepository();
    identityRepo = LaunchProfileRepository();
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('createWorkspaceWithFirstSession creates personal session without profile.json',
      () async {
    const primaryPath = '/tmp/personal-workspace';
    final store = SessionDataStore();

    final result = await store.createWorkspaceWithFirstSession(
      primaryPath,
      sessionRepo,
      sessionTeamId: '',
      rosterMembers: const [],
      identityRepository: identityRepo,
    );

    final sessions = result.snapshot.sessions
        .where((s) => s.workspaceId == result.workspaceId)
        .toList();
    expect(sessions, hasLength(1));
    expect(sessions.first.sessionTeam, '');
    expect(sessions.first.cliTeamName, '');
    expect(sessions.first.members, isEmpty);

    final workspaces = result.snapshot.workspaces
        .where((p) => p.workspaceId == result.workspaceId)
        .toList();
    expect(workspaces, hasLength(1));
    expect(
      File('${tmp.path}/workspace/workspaces/${result.workspaceId}/profile.json')
          .existsSync(),
      isFalse,
    );
  });
}
