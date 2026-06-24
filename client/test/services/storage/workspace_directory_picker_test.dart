import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/workspace_directory_picker.dart';

import '../../support/in_memory_filesystem.dart';

RuntimeContext _ctxFor(RuntimeTarget target, InMemoryFilesystem fs) =>
    RuntimeContext(
      target: target,
      filesystem: fs,
      home: '/home',
      cwd: '/home',
      appDataRoot: '/data',
      paths: const AppPaths('/data'),
    );

void main() {
  group('WorkspaceDirectoryPicker.isRemote', () {
    final picker = WorkspaceDirectoryPicker(
      resolveContext: (t) async => _ctxFor(t, InMemoryFilesystem()),
      listTargets: () async => const [],
    );

    test('only ssh ids are remote', () {
      expect(picker.isRemote('ssh:host1'), isTrue);
      expect(picker.isRemote(RuntimeTarget.localId), isFalse);
      expect(picker.isRemote('wsl:Ubuntu'), isFalse);
    });
  });

  group('WorkspaceDirectoryPicker.targetById', () {
    final ssh = RuntimeTarget.ssh('host1', label: 'Host 1');
    final picker = WorkspaceDirectoryPicker(
      resolveContext: (t) async => _ctxFor(t, InMemoryFilesystem()),
      listTargets: () async => [RuntimeTarget.local(), ssh],
    );

    test('returns the matching target', () async {
      expect(await picker.targetById('ssh:host1'), ssh);
    });

    test('falls back to local for an unknown id', () async {
      final result = await picker.targetById('ssh:missing');
      expect(result.id, RuntimeTarget.localId);
      expect(result.kind, RuntimeKind.local);
    });
  });

  group('WorkspaceDirectoryPicker.filesystemFor', () {
    test('resolves the filesystem via the injected resolveContext', () async {
      final fs = InMemoryFilesystem();
      final ssh = RuntimeTarget.ssh('host1', label: 'Host 1');
      RuntimeTarget? resolvedWith;
      final picker = WorkspaceDirectoryPicker(
        resolveContext: (t) async {
          resolvedWith = t;
          return _ctxFor(t, fs);
        },
        listTargets: () async => [RuntimeTarget.local(), ssh],
      );

      final result = await picker.filesystemFor('ssh:host1');
      expect(identical(result, fs), isTrue);
      expect(resolvedWith, ssh);
    });
  });
}
