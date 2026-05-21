import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/runtime_storage_context.dart';
import 'package:teampilot/utils/project_path_utils.dart';

void main() {
  test('session repo style paths join with POSIX separators', () {
    const root = '/home/hhoa/.local/share/com.hhoa.teampilot/projects';
    final ctx = AppPaths.pathContextForDataRoot(root);
    expect(ctx.join(root, 'projects.json'), '$root/projects.json');
    expect(ctx.join(root, 'sessions', 'id.json'), '$root/sessions/id.json');
    expect(ctx.join(root, 'projects.json'), isNot(contains(r'\')));
  });

  test('normalizeProjectPath converts Windows paths under WSL storage', () {
    if (!Platform.isWindows) return;
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(),
      paths: AppPaths('/home/hhoa/.local/share/com.hhoa.teampilot'),
      mode: StorageBackendMode.wsl,
    );
    addTearDown(RuntimeStorageContext.resetForTesting);

    final normalized = normalizeProjectPath(r'C:\Users\dev\repo');
    expect(normalized, '/mnt/c/Users/dev/repo');
    expect(normalized, isNot(contains(r'\')));
  });

  test('normalizeProjectPath keeps POSIX paths unchanged', () {
    RuntimeStorageContext.resetForTesting();
    expect(normalizeProjectPath('/tmp/work'), '/tmp/work');
    expect(
      normalizeProjectPath(r'C:\temp'),
      p.normalize(r'C:\temp'),
    );
  });
}
