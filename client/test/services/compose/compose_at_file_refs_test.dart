import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_at_file_refs.dart';

void main() {
  group('parseComposeAtFileRefs', () {
    test('parses relative and absolute @ refs', () {
      final refs = parseComposeAtFileRefs(
        'see @src/main.dart and @/tmp/Attachments/a.png please',
        workspaceRoot: '/repo',
      );
      expect(refs.map((r) => r.absolutePath).toList(), [
        '/repo/src/main.dart',
        '/tmp/Attachments/a.png',
      ]);
      expect(refs.map((r) => r.displayName).toList(), [
        'main.dart',
        'a.png',
      ]);
    });

    test('ignores /skill tokens and email-like @', () {
      final refs = parseComposeAtFileRefs(
        'user@host /commit @docs/readme.md',
        workspaceRoot: '/repo',
      );
      expect(refs.single.absolutePath, '/repo/docs/readme.md');
    });

    test('dedupes by path key keeping first order', () {
      final refs = parseComposeAtFileRefs(
        '@src/a.dart hello @src/a.dart @src/b.dart',
        workspaceRoot: '/repo',
      );
      expect(refs.map((r) => r.displayName).toList(), ['a.dart', 'b.dart']);
    });

    test('empty or skills-only yields empty', () {
      expect(
        parseComposeAtFileRefs('/commit /review', workspaceRoot: '/repo'),
        isEmpty,
      );
    });
  });
}
