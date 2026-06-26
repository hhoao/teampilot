import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

import 'in_memory_filesystem.dart';

/// Minimal [HomeTargetController] for widget tests (local home, empty ssh catalog).
HomeTargetController testHomeTargetController() {
  const root = '/tp-test-home-target';
  final fs = InMemoryFilesystem();
  final registry = RuntimeTargetRegistry(
    repo: TargetsRepository(rootDir: root, fs: fs),
    sshProfileRepo: SshProfileRepository(rootDir: root, fs: fs),
    isWindows: false,
    isAndroid: false,
  );
  return HomeTargetController(
    registry: registry,
    current: RuntimeTarget.local,
    switchTo: (_) async {},
  );
}
