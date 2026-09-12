import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_continue_overrides.dart';

void main() {
  test('continue override JSON omits launch security policy', () {
    const o = SessionContinueOverrides(
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p1',
          provider: 'anthropic',
          model: 'claude',
          effort: 'high',
        ),
      },
    );
    final json = o.toJson();
    expect(json.containsKey('launchSecurityPolicy'), isFalse);
    expect(
      (json['memberOverrides'] as Map)['builder-0'],
      isNot(contains('launchSecurityPolicy')),
    );
  });

  test('empty / missing JSON has no member overrides', () {
    expect(SessionContinueOverrides.fromJson(null).memberOverrides, isEmpty);
    expect(
      SessionContinueOverrides.fromJson(const {}).memberOverrides,
      isEmpty,
    );
  });

  test('copyWith preserves non-security continue overrides', () {
    const member = SessionMemberContinueOverride(provider: 'provider');
    const overrides = SessionContinueOverrides(
      memberOverrides: {'member': member},
    );

    expect(member.copyWith().provider, 'provider');
    expect(overrides.copyWith().memberOverrides, {'member': member});
  });
}
