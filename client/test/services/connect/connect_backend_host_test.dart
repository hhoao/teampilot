import 'dart:async';

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

  test('failed start does not commit the next kind', () async {
    final embedded = FakeEmbeddedServer(isListening: true, port: 54321);
    final system = FakeEmbeddedServer(
      isListening: false,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:sys'],
    );
    system.onStart = () async {
      throw StateError('system sshd down');
    };
    final host = ConnectBackendHost(
      embedded: embedded,
      system: system,
      settings: store,
      systemSshdSelectable: true,
    );
    await host.startSelected();

    await expectLater(
      host.select(ConnectSshBackendKind.system),
      throwsA(isA<StateError>()),
    );

    expect(host.kind, ConnectSshBackendKind.embedded);
    expect(host.current, same(embedded));
  });

  test('overlapping select calls do not interleave stop/start', () async {
    final events = <String>[];
    final releaseSystemStart = Completer<void>();
    final embedded = FakeEmbeddedServer(isListening: true, port: 54321);
    embedded.onStart = () async {
      events.add('embedded-start');
      embedded.isListening = true;
    };
    final system = FakeEmbeddedServer(
      isListening: false,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:sys'],
    );
    system.onStart = () async {
      events.add('system-start-begin');
      await releaseSystemStart.future;
      events.add('system-start-end');
      system.isListening = true;
    };
    final host = ConnectBackendHost(
      embedded: embedded,
      system: system,
      settings: store,
      systemSshdSelectable: true,
    );
    await host.startSelected();

    final toSystem = host.select(ConnectSshBackendKind.system);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['embedded-start', 'system-start-begin']);
    final toEmbedded = host.select(ConnectSshBackendKind.embedded);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['embedded-start', 'system-start-begin']);

    releaseSystemStart.complete();
    await Future.wait([toSystem, toEmbedded]);

    expect(events, [
      'embedded-start',
      'system-start-begin',
      'system-start-end',
      'embedded-start',
    ]);
    expect(host.kind, ConnectSshBackendKind.embedded);
    expect(host.current, same(embedded));
  });
}
