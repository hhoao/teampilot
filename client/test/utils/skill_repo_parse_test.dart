import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/utils/skill_repo_parse.dart';

void main() {
  group('parseGithubRepoUrl', () {
    test('accepts https github URL', () {
      final p = parseGithubRepoUrl('https://github.com/obra/superpowers');
      expect(p?.owner, 'obra');
      expect(p?.name, 'superpowers');
    });

    test('accepts .git suffix', () {
      final p = parseGithubRepoUrl('https://github.com/obra/superpowers.git');
      expect(p?.owner, 'obra');
      expect(p?.name, 'superpowers');
    });

    test('rejects owner/name shorthand', () {
      expect(parseGithubRepoUrl('obra/superpowers'), isNull);
    });

    test('rejects partial URL in owner field style', () {
      expect(parseGithubRepoUrl('https://github.com/obra'), isNull);
    });
  });

  group('formatGithubRepoUrl', () {
    test('builds canonical URL', () {
      const repo = SkillRepo(owner: 'obra', name: 'superpowers', branch: 'main');
      expect(formatGithubRepoUrl(repo), 'https://github.com/obra/superpowers');
    });
  });
}
