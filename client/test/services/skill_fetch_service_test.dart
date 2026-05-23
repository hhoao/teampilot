import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/skill_fetch_service.dart';

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

  group('skillRepoBranchCandidates', () {
    test('tries configured branch then main and master', () {
      expect(skillRepoBranchCandidates('develop'), [
        'develop',
        'main',
        'master',
      ]);
    });

    test('skips empty and HEAD', () {
      expect(skillRepoBranchCandidates(''), ['main', 'master']);
      expect(skillRepoBranchCandidates('HEAD'), ['main', 'master']);
    });
  });

  group('discoverSkillsInTarballEntries', () {
    const repo = SkillRepo(owner: 'acme', name: 'skills-repo', branch: 'main');
    final skillMd = Uint8List.fromList(
      '---\nname: my-skill\ndescription: d\n---\n'.codeUnits,
    );

    test('finds nested and root SKILL.md', () {
      final found = discoverSkillsInTarballEntries(
        entries: {
          'SKILL.md': skillMd,
          'skills/foo/SKILL.md': skillMd,
        },
        repo: repo,
        resolvedBranch: 'main',
      );
      expect(found.length, 2);
      expect(
        found.map((s) => s.directory).toSet(),
        {'skills-repo', 'skills/foo'},
      );
    });

    test('uses directory name when frontmatter has no name', () {
      final noName = Uint8List.fromList('---\ndescription: only\n---\n'.codeUnits);
      final found = discoverSkillsInTarballEntries(
        entries: {'bar/SKILL.md': noName},
        repo: repo,
        resolvedBranch: 'main',
      );
      expect(found.single.name, 'bar');
    });

    test('finds SKILL.md with Windows path separators', () {
      final found = discoverSkillsInTarballEntries(
        entries: {
          r'skills\foo\SKILL.md': skillMd,
        },
        repo: repo,
        resolvedBranch: 'main',
      );
      expect(found.single.directory, 'skills/foo');
    });
  });
}
