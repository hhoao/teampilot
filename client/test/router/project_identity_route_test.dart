import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

void main() {
  test('?as= query value decodes to the launch identity', () {
    // The route reads state.uri.queryParameters['as'] and passes it through
    // LaunchIdentity.decode. This guards the contract the route relies on.
    expect(
      LaunchIdentity.decode('squad'),
      const LaunchIdentity('squad'),
    );
    expect(
      LaunchIdentity.decode(IdentityProvisioner.defaultPersonalId),
      LaunchIdentity(IdentityProvisioner.defaultPersonalId),
    );
    expect(LaunchIdentity.decode(null), isNull);
  });
}
