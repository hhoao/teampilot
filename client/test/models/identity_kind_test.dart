import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/identity_kind.dart';

void main() {
  test('decode parses known values and defaults to personal', () {
    expect(IdentityKind.decode('team'), IdentityKind.team);
    expect(IdentityKind.decode('personal'), IdentityKind.personal);
    expect(IdentityKind.decode('  TEAM '), IdentityKind.team);
    expect(IdentityKind.decode(null), IdentityKind.personal);
    expect(IdentityKind.decode('garbage'), IdentityKind.personal);
  });

  test('value round-trips', () {
    for (final k in IdentityKind.values) {
      expect(IdentityKind.decode(k.value), k);
    }
  });
}
