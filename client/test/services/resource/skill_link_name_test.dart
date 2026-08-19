import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/resource/skill_link_name.dart';

void main() {
  test('sanitizes POSIX namespace separators into one safe link name', () {
    final linkName = targetSafeSkillLinkName(
      'review',
      namespace: 'acme/plugin',
    );

    expect(linkName, 'acme-plugin--review');
    expect(linkName, isNot(contains('/')));
    expect(linkName, isNot(contains(r'\')));
    expect(linkName, isNot(contains(':')));
  });

  test('sanitizes Windows drive and reserved punctuation', () {
    final linkName = targetSafeSkillLinkName(
      'review:plan',
      namespace: r'C:\acme/plugin',
    );

    expect(linkName, 'C-acme-plugin--review-plan');
    expect(
      linkName,
      isNot(anyOf(contains('/'), contains(r'\'), contains(':'))),
    );
  });

  test('slash invocation uses exactly the target-safe link name', () {
    const syntax = DefaultSkillInvocationSyntaxCapability();
    const name = 'acme/plugin';
    final invocation = syntax.skillInvocationText('review', namespace: name);

    expect(
      invocation,
      '/${targetSafeSkillLinkName('review', namespace: name)}',
    );
  });
}
