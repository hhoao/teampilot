import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill_acquire_spec.dart';

void main() {
  test('SkillAcquireSpec parses kind package alternatives primaryDirectory', () {
    final s = SkillAcquireSpec.fromJson({
      'kind': 'script',
      'package': 'https://example.com/install.sh',
      'alternatives': ['script:https://example.com/alt.sh'],
      'primaryDirectory': 'gstack-office-hours',
    });
    expect(s.kind, 'script');
    expect(s.package, 'https://example.com/install.sh');
    expect(s.alternatives, ['script:https://example.com/alt.sh']);
    expect(s.primaryDirectory, 'gstack-office-hours');
  });

  test('script dep expectedLocalId prefers explicit id', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      id: 'script:custom/gstack',
      acquire: const SkillAcquireSpec(
        kind: 'script',
        package: 'https://example.com/install.sh',
      ),
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    );
    expect(ref.expectedLocalId, 'script:custom/gstack');
  });

  test('script dep expectedLocalId derives from URL host/basename', () {
    final ref = SkillDependencyRef(
      name: 'gstack',
      acquire: const SkillAcquireSpec(
        kind: 'script',
        package: 'https://cdn.example.com/path/install-gstack.sh?x=1',
      ),
      repoOwner: '',
      repoName: '',
      repoBranch: 'main',
      directory: '',
    );
    expect(ref.expectedLocalId, 'script:cdn.example.com/install-gstack.sh');
  });

  test('git-dir dep without acquire keeps owner/name:basename id', () {
    const ref = SkillDependencyRef(
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      directory: 'skills/brainstorming',
      name: 'Brainstorming',
    );
    expect(ref.expectedLocalId, 'obra/superpowers:brainstorming');
    expect(ref.resolvedAcquire.kind, 'git-dir');
  });

  test('pack skill expectedLocalId uses packId and directory', () {
    const ref = SkillDependencyRef(
      id: 'garrytan/gstack:office-hours',
      packId: 'garrytan/gstack',
      name: 'Office Hours',
      repoOwner: 'garrytan',
      repoName: 'gstack',
      repoBranch: 'main',
      directory: 'office-hours',
      acquire: SkillAcquireSpec(kind: 'git-pack'),
    );
    expect(ref.expectedLocalId, 'garrytan/gstack:office-hours');
    expect(ref.resolvedAcquire.kind, 'git-pack');
  });
}
