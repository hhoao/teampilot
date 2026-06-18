import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

void main() {
  test('identity runtime paths key by identity id under identities-runtime', () {
    final layout = RuntimeLayout(teampilotRoot: '/root');
    expect(layout.identitiesRuntimeDir, '/root/identities-runtime');
    expect(
      layout.identityRuntimeDir('coding'),
      '/root/identities-runtime/coding',
    );
    expect(
      layout.identityToolDir('coding', 'claude'),
      '/root/identities-runtime/coding/claude',
    );
    expect(
      layout.identitySessionCounterFile('coding'),
      '/root/identities-runtime/coding/session-counter.json',
    );
  });
}
