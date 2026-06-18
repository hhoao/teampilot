import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_profile_ref.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';

void main() {
  test('?as= query value decodes to the launch identity', () {
    // The route reads state.uri.queryParameters['as'] and passes it through
    // LaunchProfileRef.decode. This guards the contract the route relies on.
    expect(
      LaunchProfileRef.decode('squad'),
      const LaunchProfileRef('squad'),
    );
    expect(
      LaunchProfileRef.decode(LaunchProfileProvisioner.defaultPersonalId),
      LaunchProfileRef(LaunchProfileProvisioner.defaultPersonalId),
    );
    expect(LaunchProfileRef.decode(null), isNull);
  });
}
