import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/workspace/workspace_icon_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

void main() {
  test('saveBytes stores icon under assets dir', () async {
    final tmp = await Directory.systemTemp.createTemp('workspace_icon_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final layout = WorkspaceLayout(teampilotRoot: tmp.path);
    final workspaceDir = layout.workspaceDir('abc');
    final storage = WorkspaceIconStorage(filesystem: LocalFilesystem());
    final relative = await storage.saveBytes(
      workspaceDir: workspaceDir,
      workspaceId: 'abc',
      bytes: [0x89, 0x50, 0x4E, 0x47],
      extension: 'png',
    );

    expect(relative, 'assets/icon.png');
    final absolute = WorkspaceIconStorage.absoluteIconPath(
      workspaceDir,
      relative!,
    );
    expect(await LocalFilesystem().readBytes(absolute!), isNotNull);
  });

  test('saveBytes rejects unsupported extensions', () async {
    final tmp = await Directory.systemTemp.createTemp('workspace_icon_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final layout = WorkspaceLayout(teampilotRoot: tmp.path);
    final storage = WorkspaceIconStorage(filesystem: LocalFilesystem());
    final relative = await storage.saveBytes(
      workspaceDir: layout.workspaceDir('abc'),
      workspaceId: 'abc',
      bytes: [1, 2, 3],
      extension: 'txt',
    );

    expect(relative, isNull);
  });
}
