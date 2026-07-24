import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill_install_recipe.dart';

void main() {
  test('repo dep synthesizes singleGitDir recipe', () {
    const ref = SkillDependencyRef(
      name: 'Brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/brainstorming',
    );
    expect(ref.expectedLocalId, 'obra/superpowers:brainstorming');
    final recipe = ref.resolvedRecipe!;
    expect(recipe.steps.map((s) => s.uses), ['git.sync', 'skill.install-dir']);
  });

  test('pack dep has no inline recipe; expectedLocalId uses packId', () {
    const ref = SkillDependencyRef(
      id: 'garrytan/gstack:office-hours',
      packId: 'garrytan/gstack',
      name: 'Office Hours',
      repoOwner: 'garrytan',
      repoName: 'gstack',
      repoBranch: 'main',
      directory: 'office-hours',
    );
    expect(ref.expectedLocalId, 'garrytan/gstack:office-hours');
    expect(ref.resolvedRecipe, isNull);
  });

  test('script recipe expectedLocalId from package URL', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      id: 'script:custom/gstack',
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
      recipe: SkillInstallRecipe.scriptUrl(
        url: 'https://cdn.example.com/install-gstack.sh',
        skillId: 'script:custom/gstack',
        primaryDirectory: 'gstack-office-hours',
      ),
    );
    expect(ref.expectedLocalId, 'script:custom/gstack');
    expect(ref.resolvedRecipe!.steps.single.uses, 'script.run');
  });

  test('script id derives from URL when id omitted', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
      recipe: SkillInstallRecipe.scriptUrl(
        url: 'https://cdn.example.com/install-gstack.sh',
        skillId: 'ignored-by-expected-when-no-id',
      ),
    );
    // Without explicit id, expectedLocalId scans recipe package URL.
    expect(ref.expectedLocalId, 'script:cdn.example.com/install-gstack.sh');
  });
}
