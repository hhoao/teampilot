import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/launch/staging/manifest/apply_plan.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/apply_plan_ssh_compiler.dart';
import 'package:teampilot/services/chat/launch/staging/manifest/blob_store.dart';

void main() {
  test('ensureDir symlink writeInline is one script and no tar', () async {
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyEnsureDir('/w/a'),
          ApplySymlink(linkPath: '/w/a/l', target: '/w/t'),
          ApplyWriteInline(path: '/w/a/f.txt', content: 'hi'),
          ApplyEnsureDir('/w/b'),
          ApplySymlink(linkPath: '/w/b/l', target: '/w/t'),
        ],
      ),
      blobs: MemoryBlobStore(),
    );
    expect(payload.script, isNotNull);
    expect(payload.gzipTar, isNull);
    expect(payload.script, contains('ln -sfn'));
    expect(payload.script, contains('hi'));
  });

  test(
    'blobs become one tar; script then tar order is encoded as script plus tar',
    () async {
      final blobs = MemoryBlobStore();
      final hash = contentSha256Hex([9, 8]);
      await blobs.put(hash, [9, 8]);
      final payload = await compileApplyPlanForSsh(
        plan: ApplyPlan(
          workRoot: '/w',
          ops: [
            ApplyRemove('/w/pool'),
            ApplyWriteBlob(path: '/w/pool/a.bin', sha256: hash),
          ],
        ),
        blobs: blobs,
      );
      expect(payload.script, contains("rm -rf '/w/pool'"));
      expect(payload.gzipTar, isNotNull);
      expect(payload.extractCommand, contains("tar -x -C '/w'"));
      final tar = GZipDecoder().decodeBytes(payload.gzipTar!);
      final decoded = TarDecoder().decodeBytes(tar);
      expect(decoded.findFile('pool/a.bin'), isNotNull);
    },
  );

  test('writeBlob then remove of same path omits tar member', () async {
    final blobs = MemoryBlobStore();
    final hash = contentSha256Hex([1]);
    await blobs.put(hash, [1]);
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyWriteBlob(path: '/w/a.bin', sha256: hash),
          ApplyRemove('/w/a.bin'),
        ],
      ),
      blobs: blobs,
    );
    expect(payload.gzipTar, isNull);
    expect(payload.extractCommand, isNull);
    expect(payload.script, contains("rm -rf '/w/a.bin'"));
  });

  test('later blob write survives a remove and wins per destination', () async {
    final blobs = MemoryBlobStore();
    final firstHash = contentSha256Hex([1]);
    final secondHash = contentSha256Hex([2]);
    await blobs.put(firstHash, [1]);
    await blobs.put(secondHash, [2]);

    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyWriteBlob(path: '/w/a.bin', sha256: firstHash),
          ApplyRemove('/w'),
          ApplyWriteBlob(path: '/w/a.bin', sha256: secondHash),
        ],
      ),
      blobs: blobs,
    );

    final decoded = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(payload.gzipTar!),
    );
    expect(decoded.files, hasLength(1));
    expect(decoded.findFile('a.bin')!.content, [2]);
  });

  test('tree entries are compacted individually under later remove', () async {
    final blobs = MemoryBlobStore();
    final hash = contentSha256Hex([3]);
    await blobs.put(hash, [3]);

    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyTree(
            dest: '/w/tree',
            entries: [
              ApplyTreeEntry(rel: 'keep.bin', sha256: hash),
              ApplyTreeEntry(rel: 'gone/file.bin', sha256: hash),
            ],
          ),
          ApplyRemove('/w/tree/gone'),
        ],
      ),
      blobs: blobs,
    );

    final decoded = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(payload.gzipTar!),
    );
    expect(decoded.findFile('tree/keep.bin'), isNotNull);
    expect(decoded.findFile('tree/gone/file.bin'), isNull);
  });

  test('later inline write removes the matching tree member', () async {
    final blobs = MemoryBlobStore();
    final hash = contentSha256Hex([3]);
    await blobs.put(hash, [3]);

    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [
          ApplyTree(
            dest: '/w/cursor',
            entries: [
              ApplyTreeEntry(rel: 'settings.json', sha256: hash),
              ApplyTreeEntry(rel: 'keep.json', sha256: hash),
            ],
          ),
          ApplyWriteInline(path: '/w/cursor/settings.json', content: 'session'),
        ],
      ),
      blobs: blobs,
    );

    final decoded = TarDecoder().decodeBytes(
      GZipDecoder().decodeBytes(payload.gzipTar!),
    );
    expect(decoded.findFile('cursor/settings.json'), isNull);
    expect(decoded.findFile('cursor/keep.json'), isNotNull);
    expect(payload.script, contains('session'));
  });

  test(
    'later blob write removes an earlier inline write from script',
    () async {
      final blobs = MemoryBlobStore();
      final hash = contentSha256Hex([4]);
      await blobs.put(hash, [4]);

      final payload = await compileApplyPlanForSsh(
        plan: ApplyPlan(
          workRoot: '/w',
          ops: [
            ApplyWriteInline(path: '/w/settings.json', content: 'session'),
            ApplyWriteBlob(path: '/w/settings.json', sha256: hash),
          ],
        ),
        blobs: blobs,
      );

      expect(payload.script, isNull);
      final decoded = TarDecoder().decodeBytes(
        GZipDecoder().decodeBytes(payload.gzipTar!),
      );
      expect(decoded.findFile('settings.json')!.content, [4]);
    },
  );

  test('inline heredoc cannot be terminated by its content', () async {
    const content = 'before\n__TP_MANIFEST_1__\nafter';
    final payload = await compileApplyPlanForSsh(
      plan: ApplyPlan(
        workRoot: '/w',
        ops: [ApplyWriteInline(path: "/w/a'b", content: content)],
      ),
      blobs: MemoryBlobStore(),
    );

    expect(payload.script, contains("cat > '/w/a'\"'\"'b' <<'"));
    expect(payload.script, contains(content));
    final lines = payload.script!.split('\n');
    final catLine = lines.firstWhere((line) => line.startsWith('cat >'));
    final delimiter = catLine
        .split("<<'")
        .last
        .substring(0, catLine.split("<<'").last.length - 1);
    expect(content.split('\n'), isNot(contains(delimiter)));
  });

  test('unsupported protocol and out-of-root overlays fail closed', () async {
    expect(
      () => compileApplyPlanForSsh(
        plan: const ApplyPlan(protocolVersion: 2, workRoot: '/w', ops: []),
        blobs: MemoryBlobStore(),
      ),
      throwsStateError,
    );

    final hash = contentSha256Hex([4]);
    final blobs = MemoryBlobStore();
    await blobs.put(hash, [4]);
    expect(
      () => compileApplyPlanForSsh(
        plan: ApplyPlan(
          workRoot: '/w',
          ops: [ApplyWriteBlob(path: '/other/a', sha256: hash)],
        ),
        blobs: blobs,
      ),
      throwsStateError,
    );
  });

  test('empty plan has no payloads', () async {
    final payload = await compileApplyPlanForSsh(
      plan: const ApplyPlan(workRoot: '/w', ops: []),
      blobs: MemoryBlobStore(),
    );
    expect(payload.script, isNull);
    expect(payload.gzipTar, isNull);
    expect(payload.extractCommand, isNull);
  });

  test(
    'ensureDir succeeds when the path is already a dangling symlink',
    () async {
      final tmp = await Directory.systemTemp.createTemp('apply-ensure-dir');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dest = p.join(tmp.path, 'claude-plugins-official');
      await Link(dest).create(p.join(tmp.path, 'missing-marketplace'));

      final payload = await compileApplyPlanForSsh(
        plan: ApplyPlan(workRoot: tmp.path, ops: [ApplyEnsureDir(dest)]),
        blobs: MemoryBlobStore(),
      );
      expect(payload.script, isNotNull);

      final result = await Process.run('bash', ['-c', payload.script!]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(FileSystemEntity.isLinkSync(dest), isTrue);
    },
    skip: Platform.isWindows
        ? 'executes the remote bash payload; Windows CI bash is a WSL stub'
        : false,
  );

  test(
    'ensureDir of a child does not mkdir through a dangling marketplace symlink',
    () async {
      final tmp = await Directory.systemTemp.createTemp('apply-ensure-dir');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final dest = p.join(tmp.path, 'claude-plugins-official');
      await Link(dest).create(p.join(tmp.path, 'missing-marketplace'));
      final nested = p.join(dest, '.cursor-plugin');

      final payload = await compileApplyPlanForSsh(
        plan: ApplyPlan(workRoot: tmp.path, ops: [ApplyEnsureDir(nested)]),
        blobs: MemoryBlobStore(),
      );
      expect(payload.script, isNotNull);

      final result = await Process.run('bash', ['-c', payload.script!]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(FileSystemEntity.isLinkSync(dest), isTrue);
    },
    skip: Platform.isWindows
        ? 'executes the remote bash payload; Windows CI bash is a WSL stub'
        : false,
  );

  test(
    'ensureDir of a child follows a live marketplace symlink into the target',
    () async {
      final tmp = await Directory.systemTemp.createTemp('apply-ensure-dir');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final flavor = Directory(p.join(tmp.path, 'flavor'))..createSync();
      final dest = p.join(tmp.path, 'claude-plugins-official');
      await Link(dest).create(flavor.path);
      final nested = p.join(dest, '.cursor-plugin');

      final payload = await compileApplyPlanForSsh(
        plan: ApplyPlan(workRoot: tmp.path, ops: [ApplyEnsureDir(nested)]),
        blobs: MemoryBlobStore(),
      );
      expect(payload.script, isNotNull);

      final result = await Process.run('bash', ['-c', payload.script!]);
      expect(result.exitCode, 0, reason: '${result.stderr}\n${result.stdout}');
      expect(FileSystemEntity.isLinkSync(dest), isTrue);
      expect(
        Directory(p.join(flavor.path, '.cursor-plugin')).existsSync(),
        isTrue,
      );
    },
    skip: Platform.isWindows
        ? 'executes the remote bash payload; Windows CI bash is a WSL stub'
        : false,
  );
}
