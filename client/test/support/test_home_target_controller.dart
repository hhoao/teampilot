import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/repositories/combined_ssh_profile_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

import 'in_memory_filesystem.dart';

/// Minimal [SshProfileRepository] for widget tests (in-memory fs).
SshProfileRepository testSshProfileRepository({
  String root = '/tp-test-home-target',
}) {
  return SshProfileRepository(
    rootDir: root,
    fs: InMemoryFilesystem(),
    storage: fakeHomeStorage(),
  );
}

/// Minimal work-plane execution repository for widget tests. Both sources are
/// empty in-memory catalogs, so `ssh:<id>` targets resolve as dead unless a
/// test seeds them. Widgets that construct TargetLiveness read this provider.
CombinedSshProfileRepository testCombinedSshProfileRepository({
  SshProfileRepository? workload,
  SshProfileRepository? home,
}) {
  return CombinedSshProfileRepository(
    storage: fakeHomeStorage(),
    workload:
        workload ?? testSshProfileRepository(root: '/tp-test-workload'),
    home: home ?? testSshProfileRepository(),
  );
}

/// Minimal [HomeTargetController] for widget tests (local home, empty ssh catalog).
HomeTargetController testHomeTargetController() {
  const root = '/tp-test-home-target';
  final fs = InMemoryFilesystem();
  final sshProfileRepo = SshProfileRepository(
    rootDir: root,
    fs: fs,
    storage: fakeHomeStorage(filesystem: fs),
  );
  final registry = RuntimeTargetRegistry(
    repo: TargetsRepository(rootDir: root, fs: fs),
    sshProfileRepo: sshProfileRepo,
    isWindows: false,
    isAndroid: false,
  );
  return HomeTargetController(
    registry: registry,
    current: RuntimeTarget.local,
    switchTo: (_) async {},
  );
}
