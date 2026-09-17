import 'dart:convert';

import 'package:teampilot_apply/teampilot_apply.dart';
import 'package:teampilot_fs/teampilot_fs.dart';
import 'package:test/test.dart';

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
