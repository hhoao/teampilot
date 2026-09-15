import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/connect_backend_host.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';

import '../../support/fake_embedded_server.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  late ConnectSettingsStore store;

  setUp(() {
    store = ConnectSettingsStore(
      fs: InMemoryFilesystem(),
      appDataRoot: '/app-data',
      generateHostId: () => 'abcdefghijklmnop',
    );
  });

  test('select stops embedded and starts system', () async {
    final embedded = FakeEmbeddedServer(isListening: true, port: 54321);
    final system = FakeEmbeddedServer(
      isListening: false,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:sys'],
    );
    var systemStarts = 0;
    system.onStart = () async {
      systemStarts += 1;
      system.isListening = true;
    };
    final host = ConnectBackendHost(
      embedded: embedded,
      system: system,
      settings: store,
      systemSshdSelectable: true,
    );
    await host.startSelected();
    expect(host.kind, ConnectSshBackendKind.embedded);
    await host.select(ConnectSshBackendKind.system);
    expect(host.kind, ConnectSshBackendKind.system);
    expect(host.current, same(system));
    expect(systemStarts, 1);
    expect(
      embedded.isListening,
      isFalse,
    ); // stop() should clear listening on the fake
  });

  test('system stored but not selectable still runs embedded', () async {
    await store.saveSshBackend(ConnectSshBackendKind.system);
    final host = ConnectBackendHost(
      embedded: FakeEmbeddedServer(),
      system: FakeEmbeddedServer(isEmbedded: false, port: 22),
      settings: store,
      systemSshdSelectable: false,
    );
    await host.startSelected();
    expect(host.kind, ConnectSshBackendKind.embedded);
    expect(host.current.isEmbedded, isTrue);
  });

  test('select persists requested kind even when not selectable', () async {
    final host = ConnectBackendHost(
      embedded: FakeEmbeddedServer(),
      system: FakeEmbeddedServer(isEmbedded: false, port: 22),
      settings: store,
      systemSshdSelectable: false,
    );
    await host.startSelected();
    await host.select(ConnectSshBackendKind.system);
    expect((await store.load()).sshBackend, ConnectSshBackendKind.system);
    expect(host.kind, ConnectSshBackendKind.embedded);
    expect(host.current.isEmbedded, isTrue);
  });
}
