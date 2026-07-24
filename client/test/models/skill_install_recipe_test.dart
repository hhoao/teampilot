import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/skill_install_recipe.dart';

void main() {
  test('parses steps needs exports', () {
    final r = SkillInstallRecipe.fromJson({
      'steps': [
        {
          'id': 'sync',
          'uses': 'git.sync',
          'with': {'owner': 'garrytan', 'name': 'gstack'},
        },
        {
          'id': 'bins',
          'uses': 'fs.materialize',
          'needs': ['sync'],
          'with': {'from': 'bin', 'to': '\$PACK_BIN'},
          'optional': true,
        },
      ],
      'exports': {
        'path': ['\$PACK_BIN'],
        'skills': ['garrytan/gstack:review'],
      },
    });
    expect(r.steps, hasLength(2));
    expect(r.steps[1].needs, ['sync']);
    expect(r.steps[1].optional, isTrue);
    expect(r.exports.path, ['\$PACK_BIN']);
    expect(r.exports.skills, ['garrytan/gstack:review']);
    expect(SkillInstallRecipe.fromJson(r.toJson()), r);
  });

  test('sortedSteps respects needs', () {
    final r = SkillInstallRecipe(
      steps: const [
        SkillInstallStep(
          id: 'b',
          uses: 'fs.materialize',
          needs: ['a'],
        ),
        SkillInstallStep(id: 'a', uses: 'git.sync'),
      ],
    );
    expect(r.sortedSteps().map((s) => s.id), ['a', 'b']);
  });

  test('singleGitDir sugar builds sync+install', () {
    final r = SkillInstallRecipe.singleGitDir(
      owner: 'obra',
      name: 'superpowers',
      branch: 'main',
      directory: 'skills/brainstorming',
      skillId: 'obra/superpowers:brainstorming',
    );
    expect(r.steps.map((s) => s.uses), ['git.sync', 'skill.install-dir']);
    expect(r.exports.skills, ['obra/superpowers:brainstorming']);
  });
}
