import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import 'targets_repository.dart';

/// The list of runtime targets the user can pick a home / workspace target
/// from. `targets.json` persists ssh targets; implicit `local` (and `wsl:*` on
/// Windows) are injected; ssh targets are reconciled against live ssh_profiles.
class RuntimeTargetRegistry {
  RuntimeTargetRegistry({
    required TargetsRepository repo,
    required SshProfileRepository sshProfileRepo,
    required this.isWindows,
    required this.isAndroid,
  }) : _repo = repo,
       _sshProfileRepo = sshProfileRepo;

  final TargetsRepository _repo;
  final SshProfileRepository _sshProfileRepo;
  final bool isWindows;
  final bool isAndroid;

  /// Merge persisted ssh targets with live ssh_profiles (add new, prune orphans;
  /// write back if changed) plus implicit local / wsl entries.
  Future<List<RuntimeTarget>> listTargets({String wslDistro = ''}) async {
    final file = await _repo.load();
    final profiles = await _sshProfileRepo.loadAll();
    final byId = {for (final p in profiles) p.id: p};

    final reconciled = <RuntimeTarget>[];
    var changed = false;
    for (final t in file.targets) {
      final pid = t.sshProfileId;
      if (pid != null && byId.containsKey(pid)) {
        reconciled.add(t.copyWith(label: byId[pid]!.name));
      } else {
        changed = true; // orphan dropped
      }
    }
    final existingPids = reconciled
        .map((t) => t.sshProfileId)
        .whereType<String>()
        .toSet();
    for (final p in profiles) {
      if (!existingPids.contains(p.id)) {
        reconciled.add(RuntimeTarget.ssh(p.id, label: p.name));
        changed = true;
      }
    }
    if (changed) {
      await _repo.save(file.copyWith(targets: reconciled));
    }

    return [
      RuntimeTarget.local(),
      if (isWindows && wslDistro.trim().isNotEmpty)
        RuntimeTarget.wsl(wslDistro.trim()),
      ...reconciled,
    ];
  }
}
