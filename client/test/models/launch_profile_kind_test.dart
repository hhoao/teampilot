import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_kind.dart';

void main() {
  test('decode parses known values and defaults to personal', () {
    expect(LaunchProfileKind.decode('team'), LaunchProfileKind.team);
    expect(LaunchProfileKind.decode('personal'), LaunchProfileKind.personal);
    expect(LaunchProfileKind.decode('  TEAM '), LaunchProfileKind.team);
    expect(LaunchProfileKind.decode(null), LaunchProfileKind.personal);
    expect(LaunchProfileKind.decode('garbage'), LaunchProfileKind.personal);
  });

  test('value round-trips', () {
    for (final k in LaunchProfileKind.values) {
      expect(LaunchProfileKind.decode(k.value), k);
    }
  });
}
