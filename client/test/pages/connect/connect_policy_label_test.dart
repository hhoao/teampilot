import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/pages/connect/connect_section.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets(
    'without an extra endpoint or relay the page says LAN only',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();

      expect(find.text('LAN only'), findsOneWidget);
      expect(find.text('LAN and remote'), findsNothing);
    },
  );

  testWidgets('an extra endpoint upgrades the label to LAN and remote',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    const endpoint = SshReachabilityEndpoint(
      kind: SshEndpointKind.extra,
      host: 'desktop.example.test',
      port: 2222,
    );
    await harness.cubit.openQrSession();
    await harness.cubit.saveSettings(extraEndpoints: const [endpoint], relayUrl: '');

    await tester.pumpWidget(_host(harness));
    await tester.pumpAndSettle();

    expect(find.text('LAN only'), findsNothing);
    expect(find.text('LAN and remote'), findsOneWidget);
  });

  testWidgets('a configured relay upgrades the label to LAN and remote',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.cubit.openQrSession();
    await harness.cubit.saveSettings(
      extraEndpoints: const [],
      relayUrl: 'wss://relay.example.test',
    );

    await tester.pumpWidget(_host(harness));
    await tester.pumpAndSettle();

    expect(find.text('LAN and remote'), findsOneWidget);
  });
}

SshPairingOffer _offer() => SshPairingOffer(
  v: 1,
  hostId: 'abcdefghijklmnop',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/app-data',
  endpoints: const [
    SshReachabilityEndpoint(
      kind: SshEndpointKind.lan,
      host: '192.168.1.20',
      port: 22,
    ),
  ],
  hostKeyFingerprints: const ['SHA256:host-key'],
  pairing: const SshPairingSession(
    token: 'invite-token',
    expiresAt: 1_800_000_000_000,
    url: 'https://192.168.1.20:2768/pair',
    tlsCertSha256:
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
  ),
);

class _Harness {
  _Harness() {
    final fs = InMemoryFilesystem();
    final offer = _offer();
    var keysText = '';
    final keys = AuthorizedKeysFile(
      path: '/home/alice/.ssh/authorized_keys',
      read: (_) async => keysText,
      write: (_, value) async => keysText = value,
      chmod: (_, {required mode}) async {},
    );
    deviceStore = PairedDeviceStore(fs: fs, appDataRoot: '/app-data');
    cubit = ConnectCubit(
      agent: ConnectAgentController(
        currentOffer: () => offer,
        startQrSession:
            ({
              required advertiseAddress,
              required username,
              required displayName,
              required appDataRoot,
            }) async {},
        stopQrSession: () async {},
        regenerateQr: () async {},
        updateExtraEndpoints: (_) async {},
      ),
      probeSshd: () async => const SshdPresenceSnapshot(
        listening: true,
        port: 22,
        fingerprints: ['SHA256:host-key'],
        enableHint: '',
      ),
      authorizedKeys: keys,
      deviceStore: deviceStore,
      settingsStore: ConnectSettingsStore(
        fs: fs,
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      ),
      listNetworkAddresses: () async => const [
        ConnectNetworkAddress(
          name: 'Wi-Fi',
          address: '192.168.1.20',
          isLoopback: false,
          isIpv4: true,
        ),
      ],
      username: 'alice',
      displayName: 'Alice desktop',
      appDataRoot: '/app-data',
    );
  }

  late final ConnectCubit cubit;
  late final PairedDeviceStore deviceStore;

  Future<void> dispose() => cubit.close();
}

Widget _host(_Harness harness) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: BlocProvider<ConnectCubit>.value(
        value: harness.cubit,
        child: const Scaffold(body: ConnectSection()),
      ),
    ),
  );
}
