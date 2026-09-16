import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/launch/manifest_ssh_overlay.dart';

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

  test('gzip tar round-trips file symlink and dir', () {
    final archive = Archive();
    addOverlayFile(archive, relativePath: 'a.txt', bytes: utf8.encode('hi'));
    addOverlaySymlink(archive, relativePath: 'link', target: '/opt/x');
    addOverlayDir(archive, relativePath: 'empty');
    final gz = encodeLaunchOverlayGzip(archive);
    expect(gz.length, greaterThan(32));
    final tar = GZipDecoder().decodeBytes(gz);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(
      decoded.files.map((f) => f.name),
      containsAll(['a.txt', 'link', 'empty']),
    );
    expect(decoded.findFile('link')!.symbolicLink, '/opt/x');
    expect(utf8.decode(decoded.findFile('a.txt')!.content as List<int>), 'hi');
  });

  test('extract command is short pipeline not bash -s', () {
    final cmd = launchOverlayExtractCommand(root);
    expect(cmd.startsWith('gzip -dc | tar -x -C '), isTrue);
    expect(cmd, contains("'$root'"));
    expect(utf8.encode(cmd).length, lessThan(1024));
    expect(cmd, isNot(contains('bash -s')));
  });
}
