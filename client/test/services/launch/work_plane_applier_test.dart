import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/launch/apply_plan.dart';
import 'package:teampilot/services/launch/blob_store.dart';
import 'package:teampilot/services/launch/work_plane_applier.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
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

  test('escapes workRoot fail closed before later ops', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/w/keep.txt', 'keep');
    expect(
      () => WorkPlaneApplier(
        fs: fs,
        blobs: MemoryBlobStore(),
        workRoot: '/w',
      ).apply(
        ApplyPlan(
          workRoot: '/w',
          ops: [
            ApplyRemove('/etc/passwd'),
            ApplyRemove('/w/keep.txt'),
          ],
        ),
      ),
      throwsStateError,
    );
    expect(await fs.readString('/w/keep.txt'), 'keep');
  });
}
