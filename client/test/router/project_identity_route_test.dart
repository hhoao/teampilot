import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('?as= query value decodes to the launch identity', () {
    // The route reads state.uri.queryParameters['as'] and passes it through
    // LaunchIdentity.decode. This guards the contract the route relies on.
    expect(LaunchIdentity.decode('team:abc'),
        const LaunchIdentity.team('abc'));
    expect(LaunchIdentity.decode('personal'), LaunchIdentity.personal);
    expect(LaunchIdentity.decode(null), isNull);
  });
}
