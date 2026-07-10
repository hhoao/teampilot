import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_kind.dart';

void main() {
  test('decode parses team and rejects unknown / legacy personal', () {
    expect(LaunchProfileKind.decode('team'), LaunchProfileKind.team);
    expect(LaunchProfileKind.decode('  TEAM '), LaunchProfileKind.team);
    expect(LaunchProfileKind.decode(null), LaunchProfileKind.team);
    expect(LaunchProfileKind.decode(''), LaunchProfileKind.team);
    expect(
      () => LaunchProfileKind.decode('personal'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => LaunchProfileKind.decode('garbage'),
      throwsA(isA<FormatException>()),
    );
  });

  test('value round-trips', () {
    for (final k in LaunchProfileKind.values) {
      expect(LaunchProfileKind.decode(k.value), k);
    }
  });
}
