import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/launch/staging/manifest/apply_plan.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/blob_store.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/work_plane_applier.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('writeInline uses atomicWrite', () async {
    final fs = _AtomicWriteRecordingFilesystem();
    await WorkPlaneApplier(
      fs: fs,
      blobs: MemoryBlobStore(),
      workRoot: '/w',
    ).apply(
      ApplyPlan(
        workRoot: '/w',
        ops: [ApplyWriteInline(path: '/w/a/file.txt', content: 'content')],
      ),
    );

    expect(fs.atomicWrites, ['/w/a/file.txt']);
    expect(await fs.readString('/w/a/file.txt'), 'content');
  });

  test('rm then writeBlob leaves file; writeBlob then rm removes it', () async {
    final fs = InMemoryFilesystem();
    final blobs = MemoryBlobStore();
    final bytes = utf8.encode('x');
    final hash = contentSha256Hex(bytes);
    await blobs.put(hash, bytes);
    const root = '/w';

    await WorkPlaneApplier(fs: fs, blobs: blobs, workRoot: root).apply(
      ApplyPlan(
        workRoot: root,
        ops: [
          ApplyRemove('$root/a.txt'),
          ApplyWriteBlob(path: '$root/a.txt', sha256: hash),
        ],
      ),
    );
    expect(await fs.readString('$root/a.txt'), 'x');

    await WorkPlaneApplier(fs: fs, blobs: blobs, workRoot: root).apply(
      ApplyPlan(
        workRoot: root,
        ops: [
          ApplyWriteBlob(path: '$root/a.txt', sha256: hash),
          ApplyRemove('$root/a.txt'),
        ],
      ),
    );
    expect((await fs.stat('$root/a.txt')).exists, isFalse);
  });

  test('symlink replaces leftover directory', () async {
    final fs = InMemoryFilesystem();
    await fs.ensureDir('/w/link');
    await fs.writeString('/w/link/stale.txt', 'old');
    await fs.ensureDir('/w/target');
    await WorkPlaneApplier(
      fs: fs,
      blobs: MemoryBlobStore(),
      workRoot: '/w',
    ).apply(
      ApplyPlan(
        workRoot: '/w',
        ops: [ApplySymlink(linkPath: '/w/link', target: '/w/target')],
      ),
    );
    expect(await fs.readSymlinkTarget('/w/link'), '/w/target');
  });

  test('writeBlob applies the plan mode on a real checkout', () async {
    if (Platform.isWindows) return;
    final tmp = await Directory.systemTemp.createTemp('work-plane-mode');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final fs = LocalFilesystem();
    final blobs = MemoryBlobStore();
    final bytes = utf8.encode('secret');
    final hash = contentSha256Hex(bytes);
    await blobs.put(hash, bytes);
    final path = p.join(tmp.path, '.auth', 'user');

    await WorkPlaneApplier(
      fs: fs,
      blobs: blobs,
      workRoot: tmp.path,
    ).apply(
      ApplyPlan(
        workRoot: tmp.path,
        ops: [
          ApplyWriteBlob(
            path: path,
            sha256: hash,
            mode: applyPlanPrivateFileMode,
          ),
        ],
      ),
    );

    expect(File(path).statSync().mode & 0x1ff, applyPlanPrivateFileMode);
  });

  test('middle escape fails closed before applying any ops', () async {
    final fs = InMemoryFilesystem();
    expect(
      () => WorkPlaneApplier(fs: fs, blobs: MemoryBlobStore(), workRoot: '/w')
          .apply(
            ApplyPlan(
              workRoot: '/w',
              ops: [
                ApplyWriteInline(path: '/w/created.txt', content: 'created'),
                ApplyRemove('/etc/passwd'),
                ApplyWriteInline(path: '/w/later.txt', content: 'later'),
              ],
            ),
          ),
      throwsStateError,
    );
    expect((await fs.stat('/w/created.txt')).exists, isFalse);
    expect((await fs.stat('/w/later.txt')).exists, isFalse);
  });
}

class _AtomicWriteRecordingFilesystem extends InMemoryFilesystem {
  final List<String> atomicWrites = [];

  @override
  Future<void> atomicWrite(String path, String content) {
    atomicWrites.add(path);
    return super.atomicWrite(path, content);
  }
}
