import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/app/bootstrap/home_plane_switch.dart';
import 'package:teampilot/app/bootstrap/managed_provider_control_plane.dart';
import 'package:teampilot/cubits/home_connection_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/ssh/ssh_home_connectivity_supervisor.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/home_target_store.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_registry.dart';

import '../../support/in_memory_filesystem.dart';

class _MockRuntimeContexts extends Mock implements RuntimeContextRegistry {}

class _MockSshProfiles extends Mock implements SshProfileCubit {}

class _MockManagedProviders extends Mock
    implements ManagedProviderControlPlane {}

class _MockSshHomeConnectivity extends Mock
    implements SshHomeConnectivitySupervisor {}

class _MockHomeConnectionCubit extends Mock implements HomeConnectionCubit {}

RuntimeContext _context(String appDataRoot) => RuntimeContext(
  target: RuntimeTarget.local(),
  filesystem: InMemoryFilesystem(),
  home: '/home/test',
  cwd: '/home/test',
  appDataRoot: appDataRoot,
  paths: AppPaths(appDataRoot),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(RuntimeTarget.local());
  });

  late _MockRuntimeContexts runtimeContexts;
  late _MockSshProfiles sshProfiles;
  late _MockManagedProviders managedProviders;
  late _MockSshHomeConnectivity sshHomeConnectivity;
  late _MockHomeConnectionCubit homeConnectionCubit;
  late HomeStorage storage;
  late HomeTargetStore homeTargetStore;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    runtimeContexts = _MockRuntimeContexts();
    sshProfiles = _MockSshProfiles();
    managedProviders = _MockManagedProviders();
    sshHomeConnectivity = _MockSshHomeConnectivity();
    homeConnectionCubit = _MockHomeConnectionCubit();
    storage = HomeStorage(_context('/tp/old'));
    homeTargetStore = HomeTargetStore(await SharedPreferences.getInstance());

    final nextContext = _context('/tp/new');
    when(() => runtimeContexts.home()).thenReturn(nextContext);
    when(() => runtimeContexts.dispose(any())).thenAnswer((_) async {});
    when(() => runtimeContexts.rebindHome(any())).thenAnswer((_) async {});
    when(
      () => managedProviders.invalidateForStorageContextChange(),
    ).thenAnswer((_) async {});
    when(() => homeConnectionCubit.isClosed).thenReturn(false);
  });

  HomePlaneSwitchController buildController({
    required void Function() resetNavigation,
  }) {
    var homeTarget = RuntimeTarget.termux();
    String? activeProfileId;
    return HomePlaneSwitchController(
      runtimeContexts: runtimeContexts,
      sshProfiles: sshProfiles,
      storage: storage,
      managedProviders: managedProviders,
      homeTargetStore: homeTargetStore,
      homeTargetFromId: (id) => RuntimeTarget.local(),
      sshProfileById: (_) => null,
      sshProfileConnectivityKey: (_) => 'key',
      sshHomeConnectivity: sshHomeConnectivity,
      homeConnectionCubit: homeConnectionCubit,
      applyHomeEventTransport: ({bool restart = false}) async {},
      reinstallStorageContext: () async {},
      readHomeTarget: () => homeTarget,
      writeHomeTarget: (target) => homeTarget = target,
      readActiveHomeProfileId: () => activeProfileId,
      writeActiveHomeProfileId: (id) => activeProfileId = id,
      writeWatchedConnectivityKey: (_) {},
      resetNavigation: resetNavigation,
      homeInvalidationService: () => throw UnimplementedError(),
    );
  }

  test(
    'switchHomeTarget resets navigation as soon as the plane is republished',
    () async {
      var resetCalls = 0;
      final controller = buildController(resetNavigation: () => resetCalls++);

      await controller.switchHomeTarget(RuntimeTarget.localId);

      expect(resetCalls, 1);
      verify(
        () =>
            homeConnectionCubit.rebind(profileId: null, host: null, port: null),
      ).called(1);
    },
  );

  test('a same-identity reinstall keeps the current route', () async {
    // Reconnecting the same home replaces the context instance but not the
    // plane identity (target + app data root), so the workspace route stays.
    when(() => runtimeContexts.home()).thenReturn(_context('/tp/old'));
    var resetCalls = 0;
    final controller = buildController(resetNavigation: () => resetCalls++);

    await controller.switchHomeTarget(RuntimeTarget.localId);

    expect(resetCalls, 0);
  });
}
