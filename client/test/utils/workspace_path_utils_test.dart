import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';
import 'package:teampilot/utils/workspace_path_utils.dart';

void main() {
  test('workspace layout paths join with POSIX separators', () {
    const root = '/home/hhoa/.local/share/com.hhoa.teampilot';
    final ctx = AppPaths.pathContextForDataRoot(root);
    expect(
      ctx.join(root, 'workspace', 'workspaces', 'p1', 'manifest.json'),
      '$root/workspace/workspaces/p1/manifest.json',
    );
    expect(
      ctx.join(root, 'workspace', 'workspaces', 'p1', 'sessions', 's1', 'session.json'),
      '$root/workspace/workspaces/p1/sessions/s1/session.json',
    );
    expect(
      ctx.join(root, 'ui', 'open-workspace-tabs.json'),
      isNot(contains(r'\')),
    );
  });

  test('normalizeWorkspacePath converts Windows paths under WSL storage', () {
    if (!Platform.isWindows) return;
    AppStorage.installForTesting(
      filesystem: WslFilesystem(),
      paths: AppPaths('/home/hhoa/.local/share/com.hhoa.teampilot'),
    );
    addTearDown(AppStorage.resetForTesting);

    final normalized = normalizeWorkspacePath(r'C:\Users\dev\repo');
    expect(normalized, '/mnt/c/Users/dev/repo');
    expect(normalized, isNot(contains(r'\')));
  });

  test('normalizeWorkspacePath keeps Windows paths under native storage', () {
    if (!Platform.isWindows) return;
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(),
      paths: AppPaths(r'C:\Users\dev\AppData\Roaming\com.hhoa.teampilot'),
    );
    addTearDown(AppStorage.resetForTesting);

    expect(
      normalizeWorkspacePath(r'C:\Users\dev\repo'),
      p.normalize(r'C:\Users\dev\repo'),
    );
    expect(normalizeWorkspacePath(r'C:\Users\dev\repo'), isNot(startsWith('/mnt/')));
  });

  test('normalizeWorkspacePath keeps POSIX paths unchanged', () {
    AppStorage.resetForTesting();
    expect(normalizeWorkspacePath('/tmp/work'), '/tmp/work');
    expect(
      normalizeWorkspacePath(r'C:\temp'),
      p.normalize(r'C:\temp'),
    );
  });

  test('workspaceMetadataKeys includes Windows path separator variants', () {
    if (!Platform.isWindows) return;
    AppStorage.resetForTesting();

    final keys = workspaceMetadataKeys(r'C:\Users\haung\Documents');
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
    'workspaceMetadataKeys includes Windows variants for WSL workspace paths',
    () {
      if (!Platform.isWindows) return;
      AppStorage.resetForTesting();

      final keys = workspaceMetadataKeys('/mnt/c/Users/haung/Documents');
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

  test('workspaceMetadataKeys keeps single key for POSIX paths', () {
    if (Platform.isWindows) return;
    expect(workspaceMetadataKeys('/tmp/work'), ['/tmp/work']);
  });
}
