import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/pages/connect/connect_section.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../../support/fake_embedded_server.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('revoking a phone removes its row and its key', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.deviceStore.issueDevice(
      deviceId: 'phone-1',
      publicKey: 'ssh-ed25519 AAAA1',
      deviceName: 'Pixel',
    );
    await harness.deviceStore.issueDevice(
      deviceId: 'phone-2',
      publicKey: 'ssh-ed25519 AAAA2',
      deviceName: 'Tablet',
    );
    await harness.deviceStore.issueGrant(
      hostId: 'abcdefghijklmnop',
      deviceId: 'phone-1',
      grant: 'grant-1',
    );

    await tester.pumpWidget(_host(harness));
    await tester.pumpAndSettle();

    expect(find.text('Pixel'), findsOneWidget);
    expect(find.text('Tablet'), findsOneWidget);

    final revokeButton = find.widgetWithText(TpButton, 'Revoke').first;
    await tester.ensureVisible(revokeButton);
    await tester.pumpAndSettle();
    await tester.tap(revokeButton);
    await tester.pumpAndSettle();

    expect(find.text('Pixel'), findsNothing);
    expect(find.text('Tablet'), findsOneWidget);
    // Both the key registration and the relay grant are gone.
    expect(await harness.deviceStore.hasDevice('phone-1'), isFalse);
    expect(
      await harness.deviceStore.validateGrant(
        hostId: 'abcdefghijklmnop',
        deviceId: 'phone-1',
        grant: 'grant-1',
      ),
      isFalse,
    );
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
    fs = InMemoryFilesystem();
    final offer = _offer();
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
      embeddedServer: fakeListeningEmbeddedServer,
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

  late final InMemoryFilesystem fs;
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
