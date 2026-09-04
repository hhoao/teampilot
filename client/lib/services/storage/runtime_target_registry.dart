import 'dart:async';

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
    bool Function()? hasTermuxConfig,
  }) : _repo = repo,
       _sshProfileRepo = sshProfileRepo,
       _hasTermuxConfig = hasTermuxConfig;

  final TargetsRepository _repo;
  final SshProfileRepository _sshProfileRepo;
  final bool Function()? _hasTermuxConfig;
  final bool isWindows;
  final bool isAndroid;

  /// Finds one target without reconciling or writing the persisted catalog.
  Future<RuntimeTarget?> findById(
    String targetId, {
    String wslDistro = '',
  }) async {
    final normalized = targetId.trim();
    if (normalized == RuntimeTarget.localId) return RuntimeTarget.local();
    if (isAndroid &&
        normalized == RuntimeTarget.termuxDefaultId &&
        (_hasTermuxConfig?.call() ?? false)) {
      return RuntimeTarget.termux();
    }
    if (isWindows && normalized.startsWith('wsl:')) {
      final distro = wslDistroOfId(normalized) ?? '';
      if (distro.isNotEmpty &&
          (wslDistro.trim().isEmpty || distro == wslDistro.trim())) {
        return RuntimeTarget.wsl(distro);
      }
    }
    final profiles = await _sshProfileRepo.loadAll();
    for (final profile in profiles) {
      if ('ssh:${profile.id}' == normalized) {
        return RuntimeTarget.ssh(profile.id, label: profile.name);
      }
    }
    return null;
  }

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
      if (isAndroid && (_hasTermuxConfig?.call() ?? false))
        RuntimeTarget.termux(),
      if (isWindows && wslDistro.trim().isNotEmpty)
        RuntimeTarget.wsl(wslDistro.trim()),
      ...reconciled,
    ];
  }
}
