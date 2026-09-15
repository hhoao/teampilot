import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/pages/connect/connect_section.dart';
import 'package:teampilot/services/connect/connect_backend_host.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_embedded_server.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets('shows the SSH backend selector when system sshd is selectable', (
    tester,
  ) async {
    final harness = _Harness(systemSshdSelectable: true);
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.connectSshBackendSelect), findsOneWidget);
  });

  testWidgets(
    'hides the SSH backend selector when system sshd is not selectable',
    (tester) async {
      final harness = _Harness();
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();

      expect(find.byKey(AppKeys.connectSshBackendSelect), findsNothing);
    },
  );

  testWidgets('shows a re-pair snackbar when the SSH backend changes', (
    tester,
  ) async {
    final harness = _Harness(systemSshdSelectable: true);
    addTearDown(harness.dispose);

    await tester.pumpWidget(_host(harness));
    await tester.pumpAndSettle();

    await harness.cubit.selectSshBackend(ConnectSshBackendKind.system);
    await tester.pump();

    expect(
      find.text("Paired phones must re-scan this computer's pairing code."),
      findsOneWidget,
    );
    expect(harness.cubit.state.rePairNotice, isFalse);
  });

  testWidgets(
    'shows the system revoke hint when the system backend is active',
    (tester) async {
      final harness = _Harness(systemSshdSelectable: true);
      addTearDown(harness.dispose);

      await tester.pumpWidget(_host(harness));
      await tester.pumpAndSettle();

      await harness.cubit.selectSshBackend(ConnectSshBackendKind.system);
      await tester.pumpAndSettle();

      expect(
        find.text(
          'New logins are blocked. Already-open OpenSSH sessions may stay '
          'connected until they disconnect.',
        ),
        findsOneWidget,
      );
    },
  );
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
  _Harness({bool systemSshdSelectable = false}) {
    final fs = InMemoryFilesystem();
    final offer = _offer();
    final settingsStore = ConnectSettingsStore(
      fs: fs,
      appDataRoot: '/app-data',
      generateHostId: () => 'abcdefghijklmnop',
    );
    final embedded = FakeEmbeddedServer();
    final system = FakeEmbeddedServer(
      isListening: true,
      port: 22,
      isEmbedded: false,
      hostKeyFingerprints: const ['SHA256:sys'],
    );
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
        replaceSshBackend: (_) async {},
      ),
      backends: ConnectBackendHost(
        embedded: embedded,
        system: systemSshdSelectable ? system : null,
        settings: settingsStore,
        systemSshdSelectable: systemSshdSelectable,
      ),
      deviceStore: PairedDeviceStore(fs: fs, appDataRoot: '/app-data'),
      settingsStore: settingsStore,
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
