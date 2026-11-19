import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ssh_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/cubits/ssh_workload_profile_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/ssh/ssh_connection_events.dart';
import 'package:teampilot/services/ssh/ssh_profile_connection_coordinator.dart';
import 'package:teampilot/services/ssh/ssh_profile_reconnect_policy.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';
import 'package:teampilot/widgets/ssh/ssh_connection_binder.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/ssh_connectivity_test_harness.dart';

/// Records the assembled list the binder feeds to [SshConnectionCubit].
final class _RecordingConnectionCubit extends SshConnectionCubit {
  _RecordingConnectionCubit({
    required super.factory,
    required super.coordinator,
    required super.connectivity,
  });

  final syncedProfileIds = <List<String>>[];

  @override
  Future<void> syncProfiles(List<SshProfile> profiles) async {
    syncedProfileIds.add([for (final profile in profiles) profile.id]);
    await super.syncProfiles(profiles);
  }
}

Map<String, Object?> _row(String id) => {
  'schemaVersion': 1,
  'id': id,
  'name': id,
  'host': 'h-$id',
  'port': 22,
  'username': 'u',
  'authType': 'password',
  'updatedAt': 1,
};

void main() {
  testWidgets('resyncs the host list when the home plane changes', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final plane = fakeHomeStorage(filesystem: fs);
    // Keep the device catalog (A source) separate from the home-plane server
    // catalog (B source) so the scenario is: only the home input changes.
    const deviceRoot = '/device-ssh';
    final deviceRepo = SshProfileRepository(
      rootDir: deviceRoot,
      fs: fs,
      storage: plane,
    );
    await fs.atomicWrite(
      fs.pathContext.join(deviceRoot, 'profiles.json'),
      jsonEncode([_row('p1'), _row('p2')]),
    );

    final sshProfiles = SshProfileCubit(
      profileRepository: deviceRepo,
      credentialStore: InMemorySshCredentialStore(),
    );
    await sshProfiles.load();
    final workload = SshWorkloadProfileCubit(storage: plane);
    await workload.load();

    final events = SshConnectionEvents();
    final factory = SshClientFactory(
      credentialStore: InMemorySshCredentialStore(),
      knownHostRepository: InMemorySshKnownHostRepository(),
      events: events,
      connector: (profile, {timeout = const Duration(seconds: 10)}) async {
        throw UnimplementedError('connect is not exercised by the binder');
      },
    );
    final coordinator = SshProfileConnectionCoordinator(
      factory: factory,
      events: events,
      profileResolver: (id) =>
          id.isEmpty ? null : SshProfile.fromJson(_row(id)),
      policy: const SshProfileReconnectPolicy(maxAttempts: 0),
    );
    final connectivity = TestSshConnectivity();
    final connections = _RecordingConnectionCubit(
      factory: factory,
      coordinator: coordinator,
      connectivity: connectivity,
    );

    var home = RuntimeTarget.ssh('p1', label: 'p1');
    final controller = HomeTargetController(
      registry: RuntimeTargetRegistry(
        repo: TargetsRepository(
          rootDir: plane.paths.sshProfilesDir,
          fs: fs,
        ),
        sshProfileRepo: deviceRepo,
        isWindows: false,
        isAndroid: false,
      ),
      current: () => home,
      switchTo: (_) async {},
    );

    addTearDown(() async {
      await connections.close();
      await workload.close();
      await sshProfiles.close();
      await connectivity.dispose();
      await coordinator.dispose();
    });

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<HomeStorage>.value(value: plane),
          RepositoryProvider<HomeTargetController>.value(value: controller),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<SshConnectionCubit>.value(value: connections),
            BlocProvider<SshProfileCubit>.value(value: sshProfiles),
            BlocProvider<SshWorkloadProfileCubit>.value(value: workload),
          ],
          child: const MaterialApp(
            home: SshConnectionBinder(child: SizedBox.shrink()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(connections.syncedProfileIds.last, ['p1']);

    // A home switch swaps the storage plane without touching either catalog;
    // the binder must still re-assemble against the new current home.
    home = RuntimeTarget.ssh('p2', label: 'p2');
    await plane.swap(
      RuntimeContext(
        target: home,
        filesystem: fs,
        home: plane.context.home,
        cwd: plane.context.cwd,
        appDataRoot: plane.context.appDataRoot,
        paths: plane.context.paths,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(connections.syncedProfileIds.last, ['p2']);
    expect(connections.state.hostsById.keys, contains('p2'));
    expect(connections.state.hostsById.keys, isNot(contains('p1')));
  });
}
