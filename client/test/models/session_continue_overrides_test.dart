import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_continue_overrides.dart';

void main() {
  test('SessionContinueOverrides round-trips JSON', () {
    const o = SessionContinueOverrides(
      dangerouslySkipPermissions: true,
      memberOverrides: {
        'builder-0': SessionMemberContinueOverride(
          presetId: 'p1',
          provider: 'anthropic',
          model: 'claude',
          effort: 'high',
          dangerouslySkipPermissions: false,
        ),
      },
    );
    final back = SessionContinueOverrides.fromJson(o.toJson());
    expect(back.dangerouslySkipPermissions, isTrue);
    expect(back.memberOverrides['builder-0']?.presetId, 'p1');
    expect(back.memberOverrides['builder-0']?.dangerouslySkipPermissions, isFalse);
  });

  test('empty / missing JSON is unset', () {
    expect(
      SessionContinueOverrides.fromJson(null).dangerouslySkipPermissions,
      isNull,
    );
    expect(SessionContinueOverrides.fromJson(const {}).memberOverrides, isEmpty);
  });
}
