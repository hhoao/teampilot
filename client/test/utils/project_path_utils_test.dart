import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/runtime_storage_context.dart';
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

  test('normalizeProjectPath keeps Windows paths under native storage', () {
    if (!Platform.isWindows) return;
    RuntimeStorageContext.installForTesting(
      filesystem: LocalFilesystem(),
      paths: AppPaths(r'C:\Users\dev\AppData\Roaming\com.hhoa.teampilot'),
      mode: StorageBackendMode.native,
    );
    addTearDown(RuntimeStorageContext.resetForTesting);

    expect(
      normalizeProjectPath(r'C:\Users\dev\repo'),
      p.normalize(r'C:\Users\dev\repo'),
    );
    expect(normalizeProjectPath(r'C:\Users\dev\repo'), isNot(startsWith('/mnt/')));
  });

  test('normalizeProjectPath keeps POSIX paths unchanged', () {
    RuntimeStorageContext.resetForTesting();
    expect(normalizeProjectPath('/tmp/work'), '/tmp/work');
    expect(
      normalizeProjectPath(r'C:\temp'),
      p.normalize(r'C:\temp'),
    );
  });

  test('projectMetadataKeys includes Windows path separator variants', () {
    if (!Platform.isWindows) return;
    RuntimeStorageContext.resetForTesting();

    final keys = projectMetadataKeys(r'C:\Users\haung\Documents');
    expect(
      keys,
      containsAll([
        p.normalize(r'C:\Users\haung\Documents'),
        'C:/Users/haung/Documents',
        '/mnt/c/Users/haung/Documents',
      ]),
    );
  });

  test(
    'projectMetadataKeys includes Windows variants for WSL project paths',
    () {
      if (!Platform.isWindows) return;
      RuntimeStorageContext.resetForTesting();

      final keys = projectMetadataKeys('/mnt/c/Users/haung/Documents');
      expect(keys, contains('/mnt/c/Users/haung/Documents'));
      expect(
        keys,
        containsAll([
          p.normalize(r'C:\Users\haung\Documents'),
          'C:/Users/haung/Documents',
        ]),
      );
    },
  );

  test('projectMetadataKeys keeps single key for POSIX paths', () {
    if (Platform.isWindows) return;
    expect(projectMetadataKeys('/tmp/work'), ['/tmp/work']);
  });
}
