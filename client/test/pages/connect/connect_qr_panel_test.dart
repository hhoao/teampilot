import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/connect_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_reachability.dart';
import 'package:teampilot/pages/connect/connect_qr_panel.dart';
import 'package:teampilot/pages/connect/connect_section.dart';
import 'package:teampilot/pages/config/connect_config_section.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/services/connect/sshd_presence.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/in_memory_filesystem.dart';

SshdPresenceSnapshot _sshd({required bool listening}) => SshdPresenceSnapshot(
  listening: listening,
  port: 22,
  fingerprints: listening ? const ['SHA256:host-key'] : const [],
  enableHint: 'Enable Remote Login in System Settings.',
);

SshPairingOffer _offer() => SshPairingOffer(
  v: 1,
  hostId: 'abcdefghijklmnop',
  username: 'alice',
  displayName: 'Alice desktop',
  appDataRoot: '/home/alice/.local/share/com.hhoa.teampilot',
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

Widget _harness(ConnectState state) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: Scaffold(
        body: ConnectQrPanel(
          state: state,
          onCheckSshd: () {},
          onCopyLink: () {},
          onRegenerate: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('hides pairing QR and shows enable CTA while sshd is down', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ConnectState(sshd: _sshd(listening: false))),
    );

    expect(find.byKey(AppKeys.connectQrCode), findsNothing);
    expect(find.byKey(AppKeys.connectSshdEnableCta), findsOneWidget);
  });

  testWidgets('shows pairing QR and hides enable CTA when offer is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ConnectState(sshd: _sshd(listening: true), offer: _offer())),
    );

    expect(find.byKey(AppKeys.connectQrCode), findsOneWidget);
    expect(find.byKey(AppKeys.connectSshdEnableCta), findsNothing);
  });

  testWidgets('Android guidance does not require a desktop ConnectCubit', (
    tester,
  ) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: const Scaffold(body: ConnectConfigWorkspace(isAndroid: true)),
        ),
      ),
    );

    expect(find.text('Scan a QR from desktop TeamPilot.'), findsOneWidget);
  });

  testWidgets(
    'desktop section opens and closes the QR session with visibility',
    (tester) async {
      var starts = 0;
      var stops = 0;
      final offer = _offer();
      final cubit = ConnectCubit(
        agent: ConnectAgentController(
          currentOffer: () => offer,
          startQrSession:
              ({
                required advertiseAddress,
                required username,
                required displayName,
                required appDataRoot,
              }) async {
                starts += 1;
              },
          stopQrSession: () async => stops += 1,
          regenerateQr: () async {},
          updateExtraEndpoints: (_) async {},
        ),
        probeSshd: () async => _sshd(listening: true),
        authorizedKeys: AuthorizedKeysFile(
          path: '/home/alice/.ssh/authorized_keys',
          read: (_) async => '',
          write: (_, _) async {},
          chmod: (_, {required mode}) async {},
        ),
        settingsStore: ConnectSettingsStore(
          fs: InMemoryFilesystem(),
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
      addTearDown(cubit.close);
      final theme = ThemeData(useMaterial3: true);

      Widget app(Widget child) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: Scaffold(
            body: BlocProvider.value(value: cubit, child: child),
          ),
        ),
      );

      await tester.pumpWidget(app(const ConnectSection()));
      await tester.pumpAndSettle();
      expect(starts, 1);

      await tester.pumpWidget(app(const SizedBox.shrink()));
      await tester.pump();
      expect(stops, 1);
    },
  );
}
