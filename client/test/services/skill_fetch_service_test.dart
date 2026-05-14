import 'package:teampilot/services/skill_fetch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSkillFrontmatter', () {
    test('extracts name and description', () {
      const src = '---\nname: foo\ndescription: bar baz\n---\nbody';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo');
      expect(fm.description, 'bar baz');
    });

    test('handles quoted values', () {
      const src = '---\nname: "foo bar"\ndescription: \'hello\'\n---\n';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo bar');
      expect(fm.description, 'hello');
    });

    test('missing name throws', () {
      const src = '---\ndescription: bar\n---\n';
      expect(
        () => parseSkillFrontmatter(src),
        throwsA(isA<SkillParseException>()),
      );
    });

    test('no frontmatter throws', () {
      expect(
        () => parseSkillFrontmatter('just a body'),
        throwsA(isA<SkillParseException>()),
      );
    });

    test('unterminated frontmatter throws', () {
      const src = '---\nname: foo\n';
      expect(
        () => parseSkillFrontmatter(src),
        throwsA(isA<SkillParseException>()),
      );
    });

    test('skips webServer subtree without crashing', () {
      const src =
          '---\nname: foo\ndescription: bar\nwebServer:\n  command: "x"\n  port: 3000\n---\n';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo');
      expect(fm.description, 'bar');
    });

    test('handles CRLF line endings', () {
      const src = '---\r\nname: foo\r\ndescription: bar\r\n---\r\nbody';
      final fm = parseSkillFrontmatter(src);
      expect(fm.name, 'foo');
      expect(fm.description, 'bar');
    });
  });
}
