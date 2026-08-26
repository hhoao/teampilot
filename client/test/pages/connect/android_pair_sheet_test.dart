import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/pages/connect/android_pair_sheet.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/connect/connect_pair_client.dart';
import 'package:teampilot/services/connect/paired_profile_writer.dart';
import 'package:teampilot/services/connect/pairing_http.dart';
import 'package:teampilot/services/connect/ssh_device_key.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/in_memory_filesystem.dart';

const _profile = SshProfile(
  id: 'paired-profile',
  name: 'Alice desktop',
  host: '192.168.1.20',
  username: 'alice',
);

SshPairingOffer _offer() => const SshPairingOffer(
  v: 1,
  hostId: 'AbCdEf0123_-xyZ9',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
  endpoints: [
    SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
  ],
  hostKeyFingerprints: ['SHA256:host-key'],
  pairing: SshPairingSession(
    token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
    expiresAt: 1770000000000,
    url: 'https://192.168.1.20:2768/pair',
    tlsCertSha256: 'deadbeef',
  ),
);

class _RecordingTransport implements PairingPostTransport {
  var calls = 0;

  @override
  Future<PairingPostResult> post({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) async {
    calls++;
    return const PairingPostResult(ok: true, profileHint: 'Alice desktop');
  }
}

class _LanFailRelayOkTransport implements PairingPostTransport {
  final seenUrls = <Uri>[];

  @override
  Future<PairingPostResult> post({
    required Uri url,
    required Map<String, Object?> body,
    required String tlsCertSha256,
  }) async {
    seenUrls.add(url);
    if (url.host != InternetAddress.loopbackIPv4.address) {
      throw const SocketException('LAN unreachable');
    }
    return const PairingPostResult(
      ok: true,
      profileHint: 'Alice desktop',
      relayGrant: 'grant-1',
    );
  }
}

class _ThrowingPairClient extends ConnectPairClient {
  _ThrowingPairClient(this.error);

  final Object error;

  @override
  Future<PairingPostResult> pair({
    required SshPairingOffer offer,
    required String deviceId,
    required String deviceName,
    required String publicKey,
  }) async {
    throw error;
  }
}

class _CompleterPairClient extends ConnectPairClient {
  final result = Completer<PairingPostResult>();

  @override
  Future<PairingPostResult> pair({
    required SshPairingOffer offer,
    required String deviceId,
    required String deviceName,
    required String publicKey,
  }) {
    return result.future;
  }
}

class _RecordingWriter extends PairedProfileWriter {
  _RecordingWriter()
    : super(
        profileRepository: SshProfileRepository(
          rootDir: '/unused',
          fs: InMemoryFilesystem(),
        ),
        credentialStore: InMemorySshCredentialStore(),
        knownHostRepository: InMemorySshKnownHostRepository(),
      );

  var calls = 0;

  @override
  Future<SshProfile> upsert({
    required SshPairingOffer offer,
    required PairingPostResult result,
    required String devicePem,
  }) async {
    calls++;
    return _profile;
  }
}

class _RecordingSshConnectionCubit extends SshConnectionCubit {
  _RecordingSshConnectionCubit({
    required super.factory,
    required super.coordinator,
  });

  final connectCalls = <String>[];

  @override
  Future<void> connect(String profileId) async {
    connectCalls.add(profileId);
  }
}

class _FakeSshSocket implements SSHSocket {
  final _input = StreamController<Uint8List>();
  final _done = Completer<void>();

  @override
  Stream<Uint8List> get stream => _input.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _input.close();
  }

  @override
  void destroy() {
    if (!_done.isCompleted) _done.complete();
    unawaited(_input.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}

class _Harness {
  _Harness({ConnectPairClient? pairClient, PairedProfileWriter? writer})
    : pairClient =
          pairClient ?? ConnectPairClient(transport: _RecordingTransport()),
      writer = writer ?? _RecordingWriter() {
    profileRepository = SshProfileRepository(
      rootDir: '/profiles',
      fs: InMemoryFilesystem(),
    );
    credentials = InMemorySshCredentialStore();
    profileCubit = SshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: credentials,
    );
    events = SshConnectionEvents();
    factory = SshClientFactory(
      credentialStore: credentials,
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return SSHClient(_FakeSshSocket(), username: profile.username);
      },
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
    connectionCubit = _RecordingSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
  }

  final ConnectPairClient pairClient;
  final PairedProfileWriter writer;
  late final SshProfileRepository profileRepository;
  late final InMemorySshCredentialStore credentials;
  late final SshProfileCubit profileCubit;
  late final SshConnectionEvents events;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;
  late final _RecordingSshConnectionCubit connectionCubit;

  Future<void> dispose() async {
    await connectionCubit.close();
    await profileCubit.close();
    await coordinator.dispose();
  }
}

Widget _host({
  required _Harness harness,
  required Future<String?> Function() scanCode,
  SshDeviceKeyFactory? deviceKeyFactory,
  RelayPairChannelOpener? relayTunnelOpener,
  Locale locale = const Locale('en'),
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: locale,
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SshCredentialStore>.value(
            value: harness.credentials,
          ),
          RepositoryProvider<SshProfileRepository>.value(
            value: harness.profileRepository,
          ),
          RepositoryProvider<SshKnownHostRepository>.value(
            value: InMemorySshKnownHostRepository(),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SshProfileCubit>.value(value: harness.profileCubit),
            BlocProvider<SshConnectionCubit>.value(
              value: harness.connectionCubit,
            ),
          ],
          child: Scaffold(
            body: AndroidPairSheet(
              scanCode: scanCode,
              pairClient: harness.pairClient,
              profileWriter: harness.writer,
              deviceKeyFactory:
                  deviceKeyFactory ??
                  () => (
                    pem: 'PRIVATE KEY',
                    openSshPublic: 'ssh-ed25519 AAAA test',
                  ),
              deviceId: 'phone-1',
              deviceName: 'Pixel',
              relayTunnelOpener: relayTunnelOpener,
            ),
          ),
        ),
      ),
    ),
  );
}

SshPairingOffer _offerWithRelay() => const SshPairingOffer(
  v: 1,
  hostId: 'AbCdEf0123_-xyZ9',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
  endpoints: [
    SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
    SshReachabilityEndpoint(
      kind: SshEndpointKind.relay,
      host: 'relay.example.test',
      port: 443,
    ),
  ],
  hostKeyFingerprints: ['SHA256:host-key'],
  pairing: SshPairingSession(
    token: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
    expiresAt: 1770000000000,
    url: 'https://192.168.1.20:2768/pair',
    tlsCertSha256: 'deadbeef',
  ),
  relay: SshRelayOffer(
    v: 1,
    url: 'wss://relay.example.test',
    hostId: 'AbCdEf0123_-xyZ9',
    inviteToken: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDE',
    inviteExpiresAt: 1770000000000,
  ),
);

String _unsupportedOfferCode() {
  final json = _offer().toJson()..['v'] = 2;
  final code = base64Url
      .encode(utf8.encode(jsonEncode(json)))
      .replaceAll('=', '');
  return 'teampilot://pair-ssh?code=$code';
}

void main() {
  testWidgets('scan pairs, writes one profile, and connects it', (
    tester,
  ) async {
    final writer = _RecordingWriter();
    final transport = _RecordingTransport();
    final harness = _Harness(
      pairClient: ConnectPairClient(transport: transport),
      writer: writer,
    );
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      _host(harness: harness, scanCode: () async => _offer().encode()),
    );

    expect(find.byKey(AppKeys.connectScanQr), findsOneWidget);
    expect(find.byKey(AppKeys.connectPasteCode), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pumpAndSettle();

    expect(transport.calls, 1);
    expect(writer.calls, 1);
    expect(harness.connectionCubit.connectCalls, [_profile.id]);
    expect(await harness.credentials.loadDevicePrivateKey(), 'PRIVATE KEY');
  });

  testWidgets('LAN failure falls back to the relay pair channel', (
    tester,
  ) async {
    final transport = _LanFailRelayOkTransport();
    final writer = _RecordingWriter();
    final harness = _Harness(
      pairClient: ConnectPairClient(transport: transport),
      writer: writer,
    );
    addTearDown(harness.dispose);
    final openedRelays = <SshRelayOffer>[];

    await tester.pumpWidget(
      _host(
        harness: harness,
        scanCode: () async => _offerWithRelay().encode(),
        relayTunnelOpener: (relay) async {
          openedRelays.add(relay);
          return (address: InternetAddress.loopbackIPv4, port: 45999);
        },
      ),
    );

    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pumpAndSettle();

    expect(openedRelays.single.url, 'wss://relay.example.test');
    expect(transport.seenUrls, hasLength(2));
    final loopbackPost = transport.seenUrls.last;
    expect(loopbackPost.scheme, 'https');
    expect(loopbackPost.host, InternetAddress.loopbackIPv4.address);
    expect(loopbackPost.port, 45999);
    expect(loopbackPost.path, '/pair');
    expect(writer.calls, 1);
    expect(harness.connectionCubit.connectCalls, [_profile.id]);
    expect(await harness.credentials.loadRelayGrant(_profile.id), 'grant-1');
  });

  for (final entry in const [
    (locale: Locale('en'), message: 'Code expired. Scan again.'),
    (locale: Locale('zh'), message: '配对码已过期，请重新扫描。'),
  ]) {
    testWidgets(
      'expired pairing uses the ${entry.locale.languageCode} message',
      (tester) async {
        final harness = _Harness(
          pairClient: _ThrowingPairClient(
            const PairingHttpException('expired'),
          ),
        );
        addTearDown(harness.dispose);
        await tester.pumpWidget(
          _host(
            harness: harness,
            scanCode: () async => _offer().encode(),
            locale: entry.locale,
          ),
        );

        await tester.tap(find.byKey(AppKeys.connectScanQr));
        await tester.pumpAndSettle();

        expect(find.text(entry.message), findsOneWidget);
      },
    );
  }

  testWidgets('unsupported offer version asks the user to update', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      _host(harness: harness, scanCode: () async => _unsupportedOfferCode()),
    );

    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pumpAndSettle();

    expect(find.text('Update TeamPilot to scan this code.'), findsOneWidget);
  });

  testWidgets('pair transaction completes after the sheet is removed', (
    tester,
  ) async {
    final pairClient = _CompleterPairClient();
    final writer = _RecordingWriter();
    final harness = _Harness(pairClient: pairClient, writer: writer);
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      _host(harness: harness, scanCode: () async => _offer().encode()),
    );

    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pump();
    expect(tester.widget<PopScope>(find.byType(PopScope)).canPop, isFalse);

    await tester.pumpWidget(const SizedBox());
    pairClient.result.complete(
      const PairingPostResult(ok: true, profileHint: 'Alice desktop'),
    );
    await tester.pumpAndSettle();

    expect(writer.calls, 1);
    expect(harness.connectionCubit.connectCalls, [_profile.id]);
  });

  testWidgets('corrupt stored device key is replaced before pairing', (
    tester,
  ) async {
    final transport = _RecordingTransport();
    final harness = _Harness(
      pairClient: ConnectPairClient(transport: transport),
    );
    addTearDown(harness.dispose);
    await harness.credentials.saveDevicePrivateKey('corrupt PEM');
    var generated = 0;
    await tester.pumpWidget(
      _host(
        harness: harness,
        scanCode: () async => _offer().encode(),
        deviceKeyFactory: () {
          generated++;
          return (
            pem: 'REPLACEMENT PRIVATE KEY',
            openSshPublic: 'ssh-ed25519 AAAA replacement',
          );
        },
      ),
    );

    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pumpAndSettle();

    expect(transport.calls, 1);
    expect(generated, 1);
    expect(
      await harness.credentials.loadDevicePrivateKey(),
      'REPLACEMENT PRIVATE KEY',
    );
  });

  testWidgets('valid stored Ed25519 device key is reused', (tester) async {
    final transport = _RecordingTransport();
    final harness = _Harness(
      pairClient: ConnectPairClient(transport: transport),
    );
    addTearDown(harness.dispose);
    final existing = SshDeviceKey.generate();
    await harness.credentials.saveDevicePrivateKey(existing.pem);
    await tester.pumpWidget(
      _host(
        harness: harness,
        scanCode: () async => _offer().encode(),
        deviceKeyFactory: () => throw StateError('must reuse stored key'),
      ),
    );

    await tester.tap(find.byKey(AppKeys.connectScanQr));
    await tester.pumpAndSettle();

    expect(transport.calls, 1);
    expect(await harness.credentials.loadDevicePrivateKey(), existing.pem);
  });
}
