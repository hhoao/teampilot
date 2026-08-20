import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_path_sandbox.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  late Directory tmp;
  late LocalFilesystem fs;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('catalog_sandbox_');
    fs = LocalFilesystem();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Matcher throwsUnsafePath() => throwsA(
    isA<CatalogException>().having((e) => e.code, 'code', 'unsafe_path'),
  );

  test('allows a descendant of the allowed root', () async {
    await assertSafeImportPath(
      fs: fs,
      path: p.join(tmp.path, 'skills/foo'),
      allowedRoots: [tmp.path],
    );
  });

  test('rejects /etc/passwd', () async {
    await expectLater(
      assertSafeImportPath(
        fs: fs,
        path: '/etc/passwd',
        allowedRoots: [tmp.path],
      ),
      throwsUnsafePath(),
    );
  });

  test('rejects a symlink that escapes the allowed root', () async {
    final linkPath = p.join(tmp.path, 'escape');
    await fs.createSymlink(target: '/etc/passwd', linkPath: linkPath);

    await expectLater(
      assertSafeImportPath(fs: fs, path: linkPath, allowedRoots: [tmp.path]),
      throwsUnsafePath(),
    );
  });

  test(
    'rejects a nested symlink inside an allowed SKILL.md directory',
    () async {
      final skillDir = Directory(p.join(tmp.path, 'my-skill'))..createSync();
      File(
        p.join(skillDir.path, 'SKILL.md'),
      ).writeAsStringSync('---\nname: nested\ndescription: d\n---\nbody');
      await fs.createSymlink(
        target: '/etc/passwd',
        linkPath: p.join(skillDir.path, 'secret'),
      );

      await expectLater(
        assertSafeImportPath(
          fs: fs,
          path: skillDir.path,
          allowedRoots: [tmp.path],
        ),
        throwsUnsafePath(),
      );
    },
  );
}
