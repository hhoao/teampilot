import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/project_icon_ref.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/project/project_icon_service.dart';
import 'package:teampilot/services/project/project_icon_storage.dart';

void main() {
  test('importCustomFromLocalFile stores custom icon ref', () async {
    final tmp = await Directory.systemTemp.createTemp('project_icon_service_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final source = File('${tmp.path}/source.png');
    await source.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final service = ProjectIconService(
      storage: ProjectIconStorage(filesystem: LocalFilesystem()),
    );
    final icon = await service.importCustomFromLocalFile(
      projectDir: '${tmp.path}/workspace/projects/abc',
      projectId: 'abc',
      localSourcePath: source.path,
    );

    expect(icon, const ProjectIconCustom('assets/icon.png'));
  });
}
