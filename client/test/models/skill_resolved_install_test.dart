import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill_pack_instruction.dart';

void main() {
  test('repo fields synthesize FROM + SKILLS', () {
    const ref = SkillDependencyRef(
      id: 'owner/repo:dir',
      name: 'Dir',
      directory: 'dir',
      repoOwner: 'owner',
      repoName: 'repo',
      repoBranch: 'main',
    );
    final install = ref.resolvedInstall!;
    expect(install[0], isA<FromInstruction>());
    final skills = install[1] as SkillsInstruction;
    expect(skills.includeAll, isFalse);
    expect(skills.include, ['dir']);
  });

  test('scriptUrl synthesizes SCRIPT', () {
    const ref = SkillDependencyRef(
      id: 'script:example.com/x',
      name: 'Example',
      scriptUrl: 'https://example.com/x',
      directory: 'skill-dir',
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
    );
    final script = ref.resolvedInstall!.single as ScriptInstruction;
    expect(script.url, 'https://example.com/x');
    expect(script.id, 'script:example.com/x');
    expect(script.primaryDirectory, 'skill-dir');
  });

  test('packId yields null resolvedInstall (engine loads pack)', () {
    const ref = SkillDependencyRef(
      id: 'garrytan/gstack:review',
      name: 'Review',
      packId: 'garrytan/gstack',
      directory: 'review',
      repoOwner: 'garrytan',
      repoName: 'gstack',
      repoBranch: 'main',
    );
    expect(ref.resolvedInstall, isNull);
  });

  test('fromJson throws when legacy recipe key present', () {
    expect(
      () => SkillDependencyRef.fromJson({
        'name': 'x',
        'recipe': {'steps': []},
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('scriptUrl expectedLocalId derives from URL when id omitted', () {
    const ref = SkillDependencyRef(
      name: 'gstack',
      scriptUrl: 'https://cdn.example.com/install-gstack.sh',
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    );
    expect(ref.expectedLocalId, 'script:cdn.example.com/install-gstack.sh');
  });
}
