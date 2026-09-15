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
import 'package:teampilot/services/connect/connect_backend_host.dart';
import 'package:teampilot/services/connect/connect_settings_store.dart';
import 'package:teampilot/services/connect/connect_ssh_backend.dart';
import 'package:teampilot/services/connect/paired_device_store.dart';
import 'package:teampilot/services/connect/ssh_pairing_offer.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/fake_embedded_server.dart';
import '../../support/in_memory_filesystem.dart';

SshdPresenceSnapshot _sshd({required bool listening}) => SshdPresenceSnapshot(
  listening: listening,
  port: 22,
  fingerprints: listening ? const ['SHA256:host-key'] : const [],
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
        // Mirror ConnectSection, which hosts the panel inside a scroll view.
        body: SingleChildScrollView(
          child: ConnectQrPanel(
            state: state,
            onRetry: () {},
            onCopyLink: () {},
            onRegenerate: () {},
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'hides pairing QR and shows the retry affordance while the server is down',
    (tester) async {
      await tester.pumpWidget(
        _harness(ConnectState(sshd: _sshd(listening: false))),
      );

      expect(find.byKey(AppKeys.connectQrCode), findsNothing);
      expect(
        find.text(
          'The embedded connection server failed to start. Retry or restart '
          'the app.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(AppKeys.connectSshdRetryCta), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    },
  );

  testWidgets(
    'shows macOS system sshd down copy instead of embedded when system is down',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          ConnectState(
            sshd: _sshd(listening: false),
            sshBackend: ConnectSshBackendKind.system,
            systemSshdHint: ConnectSystemSshdHint.macos,
          ),
        ),
      );

      expect(
        find.text(
          'No SSH server is listening on port 22. Enable Remote Login in '
          'Sharing settings, then retry.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The embedded connection server failed to start. Retry or restart '
          'the app.',
        ),
        findsNothing,
      );
      expect(find.byKey(AppKeys.connectSshdRetryCta), findsOneWidget);
    },
  );

  testWidgets('shows Linux system sshd down copy for linux and none hints', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        ConnectState(
          sshd: _sshd(listening: false),
          sshBackend: ConnectSshBackendKind.system,
          systemSshdHint: ConnectSystemSshdHint.linux,
        ),
      ),
    );
    expect(
      find.text(
        'No SSH server is listening on port 22. Start the OpenSSH sshd '
        'service, then retry.',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _harness(
        ConnectState(
          sshd: _sshd(listening: false),
          sshBackend: ConnectSshBackendKind.system,
          systemSshdHint: ConnectSystemSshdHint.none,
        ),
      ),
    );
    expect(
      find.text(
        'No SSH server is listening on port 22. Start the OpenSSH sshd '
        'service, then retry.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows pairing QR and hides retry CTA when offer is ready', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(ConnectState(sshd: _sshd(listening: true), offer: _offer())),
    );

    expect(find.byKey(AppKeys.connectQrCode), findsOneWidget);
    expect(find.byKey(AppKeys.connectSshdRetryCta), findsNothing);
  });

  testWidgets('fullscreen QR dialog fits wide-but-short windows', (
    tester,
  ) async {
    // shortestSide picks the width here, so a screen-sized square QR is
    // taller than the dialog's height budget.
    await tester.binding.setSurfaceSize(const Size(1000, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _harness(ConnectState(sshd: _sshd(listening: true), offer: _offer())),
    );
    // The panel lives in a scroll view in the app (ConnectSection), so it is
    // never height-constrained; mirror that here.
    await tester.dragUntilVisible(
      find.byKey(AppKeys.connectQrCode),
      find.byType(Scrollable),
      const Offset(0, -50),
    );
    await tester.tap(find.byKey(AppKeys.connectQrCode));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('fullscreen QR dialog stays in budget at large text scale', (
    tester,
  ) async {
    // zh locales and accessibility text scales render the hint taller than
    // any fixed allowance; the QR must yield to the real hint height.
    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.textScaleFactorTestValue = 2.5;
    addTearDown(() => tester.platformDispatcher.textScaleFactorTestValue = 1.0);

    await tester.pumpWidget(
      _harness(ConnectState(sshd: _sshd(listening: true), offer: _offer())),
    );
    await tester.tap(find.byKey(AppKeys.connectQrCode));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
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
      final settingsStore = ConnectSettingsStore(
        fs: InMemoryFilesystem(),
        appDataRoot: '/app-data',
        generateHostId: () => 'abcdefghijklmnop',
      );
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
        backends: ConnectBackendHost(
          embedded: fakeListeningEmbeddedServer,
          system: null,
          settings: settingsStore,
          systemSshdSelectable: false,
        ),
        deviceStore: PairedDeviceStore(
          fs: InMemoryFilesystem(),
          appDataRoot: '/app-data',
        ),
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
