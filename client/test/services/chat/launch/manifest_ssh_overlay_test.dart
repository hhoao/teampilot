import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/chat/launch/staging/manifest/manifest_ssh_overlay.dart';

void main() {
  final ctx = p.Context(style: p.Style.posix);
  const root = '/home/u/.local/share/com.hhoa.teampilot';

  test('relative path under work root', () {
    expect(
      manifestOverlayRelativePath(
        absolutePath: '$root/sessions/s1/a.json',
        workRoot: root,
        pathContext: ctx,
      ),
      'sessions/s1/a.json',
    );
  });

  test('rejects escape and absolute members', () {
    expect(
      manifestOverlayRelativePath(
        absolutePath: '/etc/passwd',
        workRoot: root,
        pathContext: ctx,
      ),
      isNull,
    );
    expect(
      manifestOverlayRelativePath(
        absolutePath: '$root/../outside',
        workRoot: root,
        pathContext: ctx,
      ),
      isNull,
    );
  });

  test('gzip tar round-trips file and dir with directory execute bits', () {
    final archive = Archive();
    addOverlayFile(archive, relativePath: 'a.txt', bytes: utf8.encode('hi'));
    addOverlayDir(archive, relativePath: 'empty');
    final gz = encodeLaunchOverlayGzip(archive);
    expect(gz.length, greaterThan(32));
    final tar = GZipDecoder().decodeBytes(gz);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(decoded.files.map((f) => f.name), containsAll(['a.txt', 'empty']));
    expect(utf8.decode(decoded.findFile('a.txt')!.content as List<int>), 'hi');
    final dir = decoded.findFile('empty')!;
    expect(dir.isDirectory, isTrue);
    expect(dir.unixPermissions & 0x49, isNot(0));
  });

  test(
    'gnu tar extract restores overlay files whose relative path exceeds 100 chars',
    () async {
      final tmp = await Directory.systemTemp.createTemp('overlay-longname');
      addTearDown(() => tmp.deleteSync(recursive: true));
      const rel =
          'workspace/workspaces/00000000-0000-4000-8000-000000000001/'
          'sessions/00000000-0000-4000-8000-000000000002/'
          'runtime/developer/claude/settings/developer.json';
      expect(rel.length, greaterThan(100));
      final archive = Archive();
      addOverlayFile(
        archive,
        relativePath: rel,
        bytes: utf8.encode('{"hooks":[]}'),
      );
      final proc = await Process.start('bash', [
        '-c',
        launchOverlayExtractCommand(tmp.path),
      ]);
      proc.stdin.add(encodeLaunchOverlayGzip(archive));
      await proc.stdin.close();
      final stderr = await utf8.decodeStream(proc.stderr);
      expect(await proc.exitCode, 0, reason: stderr);
      expect(
        File(p.join(tmp.path, rel)).readAsStringSync(),
        '{"hooks":[]}',
        reason: 'SSH overlay extract must land Claude --settings at the full path',
      );
    },
    skip: Platform.isWindows
        ? 'executes the remote gzip|tar payload; Windows CI bash is a WSL stub'
        : false,
  );

  test('extract command mkdirs workRoot then gzip|tar under 1KB', () {
    final cmd = launchOverlayExtractCommand(root);
    expect(cmd, "mkdir -p '$root' && gzip -dc | tar -x -C '$root'");
    expect(utf8.encode(cmd).length, lessThan(1024));
    expect(cmd, isNot(contains('bash -s')));
  });

  test('empty workRoot is not mapped to /', () {
    expect(
      () => launchOverlayExtractCommand(''),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('work root'),
        ),
      ),
    );
    expect(
      () => launchOverlayExtractCommand('   '),
      throwsA(isA<StateError>()),
    );
  });
}
