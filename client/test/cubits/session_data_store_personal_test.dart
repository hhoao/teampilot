import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/repositories/project_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';

void main() {
  late Directory tmp;
  late SessionRepository sessionRepo;
  late ProjectProfileRepository profileRepo;

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
    profileRepo = ProjectProfileRepository();
  });

  tearDown(() {
    RuntimeStorageContext.resetForTesting();
    tmp.deleteSync(recursive: true);
  });

  test('createProjectWithFirstSession seeds profile for personal projects',
      () async {
    const primaryPath = '/tmp/personal-project';
    final store = SessionDataStore();

    final result = await store.createProjectWithFirstSession(
      primaryPath,
      sessionRepo,
      sessionTeamId: '',
      rosterMembers: const [],
      projectProfileRepository: profileRepo,
    );

    final profile = await profileRepo.load(result.projectId);
    expect(profile, isNotNull);
    expect(profile!.projectId, result.projectId);
    // TODO: migrate to presets — .cli removed
    // expect(profile.cli, CliTool.claude);

    final sessions = result.snapshot.sessions
        .where((s) => s.projectId == result.projectId)
        .toList();
    expect(sessions, hasLength(1));
    expect(sessions.first.sessionTeam, '');
    expect(sessions.first.cliTeamName, '');
    expect(sessions.first.members, isEmpty);

    final projects = result.snapshot.projects
        .where((p) => p.projectId == result.projectId)
        .toList();
    expect(projects, hasLength(1));

    final projectDir = p.join(
      tmp.path,
      'workspace',
      'projects',
      result.projectId,
    );
    expect(Directory(projectDir).existsSync(), isTrue);
    final profileFile = File(p.join(projectDir, 'profile.json'));
    expect(profileFile.existsSync(), isTrue);
    final manifestFile = File(p.join(projectDir, 'manifest.json'));
    expect(manifestFile.existsSync(), isTrue);
    final decoded = jsonDecode(profileFile.readAsStringSync());
    expect(decoded, isA<Map>());
    expect((decoded as Map)['projectId'], result.projectId);
  });
}
