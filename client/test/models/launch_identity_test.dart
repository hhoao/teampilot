import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('personal round-trips through query encoding', () {
    expect(LaunchIdentity.personal.encode(), 'personal');
    expect(LaunchIdentity.decode('personal'), LaunchIdentity.personal);
  });

  test('team encodes/decodes with id', () {
    const id = LaunchIdentity.team('abc');
    expect(id.encode(), 'team:abc');
    expect(LaunchIdentity.decode('team:abc'), id);
  });

  test('decode returns null for missing or malformed input', () {
    expect(LaunchIdentity.decode(null), isNull);
    expect(LaunchIdentity.decode(''), isNull);
    expect(LaunchIdentity.decode('team:'), isNull);
    expect(LaunchIdentity.decode('bogus'), isNull);
  });

  test('teamId is empty for personal and the id for team', () {
    expect(LaunchIdentity.personal.teamId, '');
    expect(const LaunchIdentity.team('abc').teamId, 'abc');
  });
}
