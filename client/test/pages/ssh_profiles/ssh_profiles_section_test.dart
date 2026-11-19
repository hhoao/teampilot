import '../../support/ssh_connectivity_test_harness.dart';
import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/cubits/ssh_workload_profile_cubit.dart';
import 'package:teampilot/repositories/connection_store.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profile_connection_status.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profile_target_card.dart';
import 'package:teampilot/pages/ssh_profiles/ssh_profiles_section.dart';
import 'package:teampilot/repositories/plane_ssh_profile_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/repositories/catalog_store.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/vault/vault_service.dart';
import 'package:teampilot/services/vault/vault_unlock_gate.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import '../../support/in_memory_filesystem.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'dev',
  host: 'example.com',
  username: 'alice',
);

const _injectedA = SshProfile(
  id: 'inj-a',
  name: 'injected-a',
  host: 'a.example.com',
  username: 'alice',
);
const _injectedB = SshProfile(
  id: 'inj-b',
  name: 'injected-b',
  host: 'b.example.com',
  username: 'bob',
);

class _ControllableSshConnectionCubit extends SshConnectionCubit {
  _ControllableSshConnectionCubit({
    required SshClientFactory factory,
    required SshProfileConnectionCoordinator coordinator,
  }) : super(
        factory: factory,
        coordinator: coordinator,
        connectivity: TestSshConnectivity(),
      );

  final connectCalls = <String>[];
  final disconnectCalls = <String>[];

  void seed(SshConnectionState next) => emit(next);

  @override
  Future<void> connect(String profileId, {bool switchHome = true}) async {
    connectCalls.add(profileId);
  }

  @override
  Future<void> disconnect(String profileId) async {
    disconnectCalls.add(profileId);
  }
}

class _SeededSshProfileCubit extends SshProfileCubit {
  _SeededSshProfileCubit({
    required super.profileRepository,
    required super.credentialStore,
    required List<SshProfile> profiles,
  }) {
    emit(
      SshProfileState(profiles: profiles, selectedProfileId: profiles.first.id),
    );
  }
}

class _Harness {
  _Harness() {
    events = SshConnectionEvents();
    credentialStore = InMemorySshCredentialStore();
    knownHosts = InMemorySshKnownHostRepository();
    factory = SshClientFactory(
      credentialStore: credentialStore,
      knownHostRepository: knownHosts,
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        return _InstantAuthClient();
      },
    );
    coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (_) => null,
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
  }

  late final SshConnectionEvents events;
  late final InMemorySshCredentialStore credentialStore;
  late final InMemorySshKnownHostRepository knownHosts;
  late final SshClientFactory factory;
  late final SshProfileConnectionCoordinator coordinator;

  _ControllableSshConnectionCubit createConnectionCubit() {
    return _ControllableSshConnectionCubit(
      factory: factory,
      coordinator: coordinator,
    );
  }

  Future<void> dispose() => coordinator.dispose();
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
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
  Future get done async {}
}

class _LockedVault implements VaultService {
  @override
  bool get isEncrypted => false;

  @override
  bool get isUnlocked => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SshConnectionState _stateWithHost({
  required SshHostUiStatus status,
  String? errorDetail,
}) {
  return SshConnectionState(
    hostsById: {
      _profile.id: SshHostConnectionVm(
        profileId: _profile.id,
        label: _profile.name,
        host: _profile.host,
        status: status,
        errorDetail: errorDetail,
      ),
    },
    profileOrder: [_profile.id],
  );
}

Future<Widget> _host({
  required SshProfileCubit profileCubit,
  required SshConnectionCubit connectionCubit,
  required SshCredentialStore credentialStore,
  required TerminalTransportFactory transportFactory,
  required SshProfileRepository profileRepository,
  VaultService? vault,
  VaultUnlockGate? vaultUnlockGate,
  List<SshProfile>? profiles,
  Future<void> Function()? onRefresh,
  Future<void> Function(String profileId)? onDelete,
  Cubit<SshProfileState>? injectedCubit,
  SshProfileRepository? injectedRepository,
}) async {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: appLocalizationsSupportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SshCredentialStore>.value(value: credentialStore),
          RepositoryProvider<TerminalTransportFactory>.value(
            value: transportFactory,
          ),
          RepositoryProvider<SshProfileRepository>.value(
            value: profileRepository,
          ),
          if (vault != null)
            RepositoryProvider<VaultService>.value(value: vault),
          if (vaultUnlockGate != null)
            RepositoryProvider<VaultUnlockGate>.value(value: vaultUnlockGate),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SshProfileCubit>.value(value: profileCubit),
            BlocProvider<SshConnectionCubit>.value(value: connectionCubit),
          ],
          child: Scaffold(
            body: SingleChildScrollView(
              child: SshProfilesSection(
                profiles: profiles ?? const [_profile],
                onRefresh: onRefresh ?? () async {},
                onDelete: onDelete ?? (_) async {},
                repository: injectedRepository ?? profileRepository,
                profileCubit: injectedCubit ?? profileCubit,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;
  late SshProfileRepository profileRepository;
  late _Harness harness;
  late _ControllableSshConnectionCubit connectionCubit;
  late _SeededSshProfileCubit profileCubit;
  late TerminalTransportFactory transportFactory;
  late AppLocalizations l10n;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ssh_profiles_section_');
    profileRepository = SshProfileRepository(
      rootDir: tempDir.path,
      storage: fakeHomeStorage(),
    );
    await profileRepository.save(_profile);

    harness = _Harness();
    connectionCubit = harness.createConnectionCubit();
    profileCubit = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: const [_profile],
    );
    transportFactory = TerminalTransportFactory(
      sshProfileRepository: profileRepository,
      sshCredentialStore: harness.credentialStore,
      sshKnownHostRepository: harness.knownHosts,
      sshClientFactory: harness.factory,
    );
    l10n = await const AppLocalizationsCompatDelegate().load(
      const Locale('en'),
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await connectionCubit.close();
    await profileCubit.close();
    await harness.dispose();
    await tempDir.delete(recursive: true);
  });

  testWidgets('Android shows Scan QR as the primary SSH action', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    expect(find.byKey(AppKeys.connectScanQr), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('card status comes from SshConnectionCubit', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.connected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    expect(find.text(l10n.sshProfile.statusConnected), findsOneWidget);
    expect(find.text(l10n.sshProfile.disconnect), findsOneWidget);
  });

  testWidgets('Connect calls SshConnectionCubit.connect', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfile.connect));
    await tester.pump();

    expect(connectionCubit.connectCalls, [_profile.id]);
  });

  testWidgets('Disconnect calls SshConnectionCubit.disconnect', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.connected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfile.disconnect));
    await tester.pump();

    expect(connectionCubit.disconnectCalls, [_profile.id]);
  });

  testWidgets('card layout does not overflow at narrow width', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLocalizationsSupportedLocales,
        locale: const Locale('en'),
        theme: theme,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            theme.colorScheme,
            scale: 1.0,
            controlScale: AppTypographyScale.standard.multiplier,
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(8),
              child: SshProfileTargetCard(
                profile: _profile,
                status: SshProfileConnectionStatus.disconnected,
                testing: false,
                busy: false,
                onTest: () {},
                onConnect: () {},
                onDisconnect: () {},
                onEdit: () {},
                onDelete: () {},
                onRefresh: () {},
                onConfigure: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
    expect(find.text(l10n.sshProfile.connect), findsNothing);
  });

  testWidgets('Test does not mark Cubit connected', (tester) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
      ),
    );

    await tester.tap(find.text(l10n.sshProfile.test));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // "Test" shows an indeterminate spinner while the async SSH probe runs,
    // so pumpAndSettle() never settles under fake async. Pump a bounded
    // amount instead — the assertions only need the UI to have reacted to
    // the tap, not the probe to finish.
    await tester.pump(const Duration(milliseconds: 100));

    expect(connectionCubit.connectCalls, isEmpty);
    expect(
      connectionCubit.state.hostsById[_profile.id]!.status,
      SshHostUiStatus.disconnected,
    );
    expect(find.text(l10n.sshProfile.statusConnected), findsNothing);
    expect(find.text(l10n.sshProfile.statusDisconnected), findsOneWidget);
  });

  testWidgets(
    'Connect on a vault-backed target aborts when unlock is cancelled',
    (tester) async {
      connectionCubit.seed(
        _stateWithHost(status: SshHostUiStatus.disconnected),
      );
      final vaultProfile = _profile.copyWith(vaultEntryId: 'entry-1');
      final seeded = _SeededSshProfileCubit(
        profileRepository: profileRepository,
        credentialStore: harness.credentialStore,
        profiles: [vaultProfile],
      );
      addTearDown(seeded.close);
      var prompts = 0;
      final vault = _LockedVault();
      final gate = VaultUnlockGate(
        vault: vault,
        prompt: () async {
          prompts++;
          return false;
        },
      );

      await tester.pumpWidget(
        await _host(
          profileCubit: seeded,
          connectionCubit: connectionCubit,
          credentialStore: harness.credentialStore,
          transportFactory: transportFactory,
          profileRepository: profileRepository,
          profiles: [vaultProfile],
          vault: vault,
          vaultUnlockGate: gate,
        ),
      );

      await tester.tap(find.text(l10n.sshProfile.connect));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(prompts, 1);
      expect(connectionCubit.connectCalls, isEmpty);
      expect(find.text(l10n.vault.lockedSaveBlocked), findsOneWidget);
      // Let the toast's dismissal timer expire before the tree is disposed.
      await tester.pump(const Duration(seconds: 6));
    },
  );

  testWidgets('Test on a vault-backed target aborts when unlock is cancelled', (
    tester,
  ) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));
    final vaultProfile = _profile.copyWith(vaultEntryId: 'entry-1');
    final seeded = _SeededSshProfileCubit(
      profileRepository: profileRepository,
      credentialStore: harness.credentialStore,
      profiles: [vaultProfile],
    );
    addTearDown(seeded.close);
    var prompts = 0;
    final vault = _LockedVault();
    final gate = VaultUnlockGate(
      vault: vault,
      prompt: () async {
        prompts++;
        return false;
      },
    );

    await tester.pumpWidget(
      await _host(
        profileCubit: seeded,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        profiles: [vaultProfile],
        vault: vault,
        vaultUnlockGate: gate,
      ),
    );

    await tester.tap(find.text(l10n.sshProfile.test));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(prompts, 1);
    expect(connectionCubit.connectCalls, isEmpty);
    expect(find.text(l10n.vault.lockedSaveBlocked), findsOneWidget);
    // Let the toast's dismissal timer expire before the tree is disposed.
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('list comes from injected A-source profiles, not the cubit state', (
    tester,
  ) async {
    // The watched SshProfileCubit holds only [_profile]; the injected list is
    // deliberately different. A section still reading context.watch would
    // render the cubit's single 'dev' card instead.
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        profiles: const [_injectedA, _injectedB],
      ),
    );

    expect(find.byType(SshProfileTargetCard), findsNWidgets(2));
    expect(find.text('injected-a'), findsOneWidget);
    expect(find.text('injected-b'), findsOneWidget);
    expect(find.text('dev'), findsNothing);
  });

  testWidgets('list comes from injected B-source (workload cubit) profiles', (
    tester,
  ) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));
    final storage = fakeHomeStorage();
    final workloadCubit = _workloadCubit(storage);
    addTearDown(workloadCubit.close);
    final planeRepository = PlaneSshProfileRepository(
      storage: storage,
      connections: ConnectionStore(rootDir: '/device', fs: storage.fs),
      catalog: CatalogStore(storage: storage),
    );

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        injectedCubit: workloadCubit,
        injectedRepository: planeRepository,
        profiles: const [_injectedA],
      ),
    );

    // The workload cubit's own state is empty; the rendered row must be the
    // injected B-source profile, proving the list is driven by the parameter.
    expect(workloadCubit.state.profiles, isEmpty);
    expect(find.byType(SshProfileTargetCard), findsOneWidget);
    expect(find.text('injected-a'), findsOneWidget);
    expect(find.text('dev'), findsNothing);
  });

  testWidgets('card refresh invokes the injected onRefresh callback', (
    tester,
  ) async {
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));
    var refreshes = 0;

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        onRefresh: () async => refreshes++,
      ),
    );

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();

    expect(refreshes, 1);
  });

  testWidgets('delete confirmation invokes the injected onDelete callback', (
    tester,
  ) async {
    // The section must be source-agnostic: it forwards deletes to the injected
    // callback instead of reading a SshProfileCubit from context.
    connectionCubit.seed(_stateWithHost(status: SshHostUiStatus.disconnected));
    final deleted = <String>[];

    await tester.pumpWidget(
      await _host(
        profileCubit: profileCubit,
        connectionCubit: connectionCubit,
        credentialStore: harness.credentialStore,
        transportFactory: transportFactory,
        profileRepository: profileRepository,
        onDelete: (id) async => deleted.add(id),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(deleted, [_profile.id]);
  });
}


SshWorkloadProfileCubit _workloadCubit(HomeStorage storage) =>
    SshWorkloadProfileCubit(
      storage: storage,
      connections: ConnectionStore(rootDir: '/device', fs: storage.fs),
    );
