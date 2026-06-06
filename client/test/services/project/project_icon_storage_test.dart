import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/project/project_icon_storage.dart';

void main() {
  test('saveBytes stores icon under icons dir', () async {
    final tmp = await Directory.systemTemp.createTemp('project_icon_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final storage = ProjectIconStorage(filesystem: LocalFilesystem());
    final appProjectsDir = '${tmp.path}/projects';
    final relative = await storage.saveBytes(
      appProjectsDir: appProjectsDir,
      projectId: 'abc',
      bytes: [0x89, 0x50, 0x4E, 0x47],
      extension: 'png',
    );

    expect(relative, 'icons/abc.png');
    final absolute = ProjectIconStorage.absoluteIconPath(
      appProjectsDir,
      relative!,
    );
    expect(await LocalFilesystem().readBytes(absolute!), isNotNull);
  });

  test('saveBytes rejects unsupported extensions', () async {
    final tmp = await Directory.systemTemp.createTemp('project_icon_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final storage = ProjectIconStorage(filesystem: LocalFilesystem());
    final relative = await storage.saveBytes(
      appProjectsDir: '${tmp.path}/projects',
      projectId: 'abc',
      bytes: [1, 2, 3],
      extension: 'txt',
    );

    expect(relative, isNull);
  });
}
