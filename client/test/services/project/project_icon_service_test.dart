import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_icon_ref.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/workspace/workspace_icon_service.dart';
import 'package:teampilot/services/workspace/workspace_icon_storage.dart';

void main() {
  test('importCustomFromLocalFile stores custom icon ref', () async {
    final tmp = await Directory.systemTemp.createTemp('workspace_icon_service_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final source = File('${tmp.path}/source.png');
    await source.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final service = WorkspaceIconService(
      storage: WorkspaceIconStorage(filesystem: LocalFilesystem()),
    );
    final icon = await service.importCustomFromLocalFile(
      workspaceDir: '${tmp.path}/workspace/workspaces/abc',
      workspaceId: 'abc',
      localSourcePath: source.path,
    );

    expect(icon, const WorkspaceIconCustom('assets/icon.png'));
  });
}
