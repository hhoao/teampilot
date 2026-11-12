import '../support/ssh_connectivity_test_harness.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/remote_connections_page.dart';
import 'package:teampilot/pages/remote_targets_page.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/storage/home_connect_attempt.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../support/in_memory_filesystem.dart';

/// Avoids real connection attempts; the status card only reads state.
class _StubSshConnectionCubit extends SshConnectionCubit {
  _StubSshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
  }) : super(
        factory: factory,
        coordinator: coordinator,
        connectivity: TestSshConnectivity(),
      );

  @override
  Future<void> connect(String profileId, {bool switchHome = true}) async {}

  @override
  Future<void> disconnect(String profileId) async {}
}

void main() {
  late Directory tempDir;
  late SshProfileRepository profileRepository;
  late InMemorySshCredentialStore credentialStore;
  late _StubSshConnectionCubit connectionCubit;
  late SshProfileCubit profileCubit;
  late SshProfileConnectionCoordinator coordinator;
  late AppLocalizations l10n;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('remote_conn_status_');
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      fs: InMemoryFilesystem(),
      storage: fakeHomeStorage(),
    );
    credentialStore = InMemorySshCredentialStore();
    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: credentialStore,
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
    connectionCubit = _StubSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
    profileCubit = SshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: credentialStore,
    );
    l10n = await const AppLocalizationsCompatDelegate().load(
      const Locale('en'),
    );
  });

  tearDown(() async {
    await connectionCubit.close();
    await profileCubit.close();
    await coordinator.dispose();
    await tempDir.delete(recursive: true);
  });

  HomeConnectionCubit buildHomeCubit({
    String? host = 'example.com',
    int? port = 2222,
    Future<void> Function()? cancelRetry,
  }) {
    return HomeConnectionCubit(
      connect: () async =>
          const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
      cancelRetry: cancelRetry ?? () async {},
      resumeRetry: () async {},
      onConnected: () {},
      host: host,
      port: port,
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    HomeConnectionCubit? homeCubit,
    bool embedded = false,
  }) async {
    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
        locale: const Locale('en'),
        theme: theme,
        // Wrap every route (including pushed ones) so the targets page reached
        // through 「切换连接」 also sees the theme and the cubits.
        builder: (context, child) => TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<SshProfileCubit>.value(value: profileCubit),
              BlocProvider<SshConnectionCubit>.value(value: connectionCubit),
              if (homeCubit != null)
                BlocProvider<HomeConnectionCubit>.value(value: homeCubit),
            ],
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: RemoteConnectionsPage(embedded: embedded),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unreachable shows host:port, error kind and retry now', (
    tester,
  ) async {
    final homeCubit = buildHomeCubit();
    addTearDown(homeCubit.close);
    homeCubit.markInitial(
      const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
    );

    await pumpPage(tester, homeCubit: homeCubit);

    expect(
      find.text(
        l10n.home.connectionUnreachable(host: 'example.com', port: 2222),
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.home.connectionErrorTcp), findsOneWidget);
    expect(find.text(l10n.home.connectionRetryNow), findsOneWidget);
    expect(find.text(l10n.home.connectionSwitch), findsOneWidget);
    expect(find.text(l10n.home.connectionCancelRetry), findsNothing);
    // The target list now lives on its own page; the status view shows the
    // card alone.
    expect(find.text(l10n.sshProfile.sEmpty), findsNothing);
  });

  testWidgets('switch connection opens the targets page', (tester) async {
    final homeCubit = buildHomeCubit();
    addTearDown(homeCubit.close);
    homeCubit.markInitial(
      const HomeConnectResult.unreachable(HomeErrorKind.tcpUnreachable),
    );

    await pumpPage(tester, homeCubit: homeCubit);
    await tester.tap(find.text(l10n.home.connectionSwitch));
    await tester.pumpAndSettle();

    expect(find.byType(RemoteTargetsPage), findsOneWidget);
  });

  testWidgets('reconnecting shows attempt count and cancel calls cancelRetry', (
    tester,
  ) async {
    var cancelCalls = 0;
    final homeCubit = buildHomeCubit(cancelRetry: () async => cancelCalls++);
    addTearDown(homeCubit.close);
    homeCubit.markBackgroundAttempt(3);

    await pumpPage(tester, homeCubit: homeCubit);

    expect(find.text(l10n.home.connectionRetrying(count: 3)), findsOneWidget);
    expect(find.text(l10n.home.connectionCancelRetry), findsOneWidget);
    // While auto-retrying, only the stop action is offered — never both.
    expect(find.text(l10n.home.connectionRetryNow), findsNothing);

    await tester.tap(find.text(l10n.home.connectionCancelRetry));
    await tester.pump();

    expect(cancelCalls, 1);
    expect(homeCubit.state.status, HomeConnectionStatus.unreachable);
    expect(find.text(l10n.home.connectionCancelRetry), findsNothing);
    expect(find.text(l10n.home.connectionRetryNow), findsOneWidget);
  });

  testWidgets('host identity change shows the re-pair hint', (tester) async {
    final homeCubit = buildHomeCubit();
    addTearDown(homeCubit.close);
    homeCubit.markUnreachable(HomeErrorKind.hostIdentityChanged);

    await pumpPage(tester, homeCubit: homeCubit);

    expect(find.text(l10n.home.connectionErrorHostKey), findsOneWidget);
    expect(find.text(l10n.home.connectionSwitch), findsOneWidget);
    expect(find.text(l10n.home.connectionRetryNow), findsOneWidget);
    expect(find.text(l10n.home.connectionCancelRetry), findsNothing);
  });

  testWidgets('connected status renders no status card', (tester) async {
    final homeCubit = buildHomeCubit();
    addTearDown(homeCubit.close);
    homeCubit.markReconnected();

    await pumpPage(tester, homeCubit: homeCubit);

    expect(find.text(l10n.home.connectionRetryNow), findsNothing);
    expect(find.text(l10n.home.connectionSwitch), findsNothing);
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);
  });

  testWidgets('missing cubit provider renders the page without a card', (
    tester,
  ) async {
    await pumpPage(tester);

    expect(find.text(l10n.home.connectionRetryNow), findsNothing);
    expect(find.text(l10n.home.connectionSwitch), findsNothing);
    expect(find.text(l10n.sshProfile.sEmpty), findsOneWidget);
  });
}
