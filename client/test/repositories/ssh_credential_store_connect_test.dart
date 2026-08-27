import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';

void main() {
  test(
    'device key is global; relay grant is per profile and deleted with deleteAll',
    () async {
      final store = InMemorySshCredentialStore();

      await store.saveDevicePrivateKey('PEM');
      await store.saveRelayGrant('p1', 'grant');
      await store.deleteAll('p1');

      expect(await store.loadDevicePrivateKey(), 'PEM');
      expect(await store.loadRelayGrant('p1'), isNull);
    },
  );
}
