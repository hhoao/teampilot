import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource/resource_kind.dart';

void main() {
  test('EffectiveResourceSet.of returns the kind list or empty', () {
    const ref = ResourceRef(
      id: 'demo',
      linkName: 'demo-skill',
      sourceDir: '/lib/skills/demo-skill',
    );
    const set = EffectiveResourceSet({
      ResourceKind.skill: [ref],
    });
    expect(set.of(ResourceKind.skill), [ref]);
    expect(set.of(ResourceKind.plugin), isEmpty);
  });
}
