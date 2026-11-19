import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/workspace_directory_picker.dart';

import '../../support/in_memory_filesystem.dart';

/// Remote counterpart of [InMemoryFilesystem]: the picker must reject an ssh
/// target that resolved to a non-remote backend, so ssh contexts in tests need
/// `isRemote == true`.
class _RemoteInMemoryFilesystem extends InMemoryFilesystem {
  @override
  bool get isRemote => true;
}

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

    test(
      'keeps an id missing from the catalog on its own kind, not local',
      () async {
        // The home SSH target is bound in the device-local (A) catalog and may
        // be absent from the workspace (B) catalog; resolving it as `local`
        // makes the remote browser list the device disk instead.
        final result = await picker.targetById('ssh:missing');
        expect(result.id, 'ssh:missing');
        expect(result.kind, RuntimeKind.ssh);
        expect(result.sshProfileId, 'missing');
      },
    );

    test('still resolves the local id to the local target', () async {
      final result = await picker.targetById(RuntimeTarget.localId);
      expect(result, RuntimeTarget.local());
    });
  });

  group('WorkspaceDirectoryPicker.filesystemFor', () {
    test('resolves the filesystem via the injected resolveContext', () async {
      final fs = _RemoteInMemoryFilesystem();
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

    test('resolves an ssh id missing from the catalog as ssh', () async {
      RuntimeTarget? resolvedWith;
      final picker = WorkspaceDirectoryPicker(
        resolveContext: (t) async {
          resolvedWith = t;
          return _ctxFor(t, _RemoteInMemoryFilesystem());
        },
        listTargets: () async => const [],
      );

      await picker.filesystemFor('ssh:home');
      expect(resolvedWith?.kind, RuntimeKind.ssh);
      expect(resolvedWith?.sshProfileId, 'home');
    });

    test(
      'rejects an ssh target that resolved to a non-remote filesystem',
      () async {
        // An ssh target that resolves native means the profile was not found in
        // either catalog; browsing that backend lists the device disk.
        final picker = WorkspaceDirectoryPicker(
          resolveContext: (t) async => _ctxFor(t, InMemoryFilesystem()),
          listTargets: () async => [RuntimeTarget.ssh('host1', label: 'H1')],
        );

        await expectLater(
          picker.filesystemFor('ssh:host1'),
          throwsA(isA<WorkspaceDirectoryPickerException>()),
        );
      },
    );

    test('contextFor exposes the resolved home to the browser', () async {
      final picker = WorkspaceDirectoryPicker(
        resolveContext: (t) async => _ctxFor(t, _RemoteInMemoryFilesystem()),
        listTargets: () async => [RuntimeTarget.ssh('host1', label: 'H1')],
      );

      final ctx = await picker.contextFor('ssh:host1');
      expect(ctx.home, '/home');
      expect(ctx.fs.isRemote, isTrue);
    });
  });
}
