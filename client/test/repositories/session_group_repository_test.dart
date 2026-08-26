import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/repositories/session_group_repository.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  late SessionGroupRepository repository;
  late WorkspaceLayout layout;

  setUp(() {
    repository = SessionGroupRepository();
    layout = WorkspaceLayout(teampilotRoot: AppStorage.paths.basePath);
  });

  test('missing file loads empty without creating it', () async {
    final file = await repository.load('ws-1');
    expect(file.groups, isEmpty);
    expect(File(layout.sessionGroupsFile('ws-1')).existsSync(), isFalse);
  });

  test('save creates parent dirs and load round-trips', () async {
    const file = SessionGroupsFile(
      groups: [
        SessionGroup(id: 'g1', name: '待办', sessionIds: ['s1'], collapsed: true),
      ],
    );
    await repository.save('ws-1', file);
    expect(File(layout.sessionGroupsFile('ws-1')).existsSync(), isTrue);
    expect(await repository.load('ws-1'), file);
  });

  test('corrupt json loads empty', () async {
    final path = layout.sessionGroupsFile('ws-1');
    await File(path).parent.create(recursive: true);
    await File(path).writeAsString('{broken');
    expect((await repository.load('ws-1')).groups, isEmpty);
  });

  test('empty workspace id is a no-op', () async {
    await repository.save('  ', const SessionGroupsFile());
    expect((await repository.load('')).groups, isEmpty);
    expect((await repository.load('')).version, SessionGroupsFile.currentVersion);
  });
}
