import 'dart:async';

import '../../models/runtime_target.dart';
import '../../repositories/ssh_profile_repository.dart';
import 'targets_repository.dart';

/// The list of runtime targets the user can pick a workspace / home target
/// from. `targets.json` persists ssh targets; implicit `local` (and `wsl:*` on
/// Windows) are injected; ssh targets are reconciled against live profiles.
///
/// [sshProfileRepo] decides which profile catalog the targets come from. The
/// workspace machine lists bind it to the home-plane workload catalog (B
/// source); the home-target palette binds it to the device-local home-binding
/// catalog (A source). The two are deliberately separate instances so a home
/// selection never reconciles the workload `targets.json` against home profiles.
///
/// [repo] is the persisted workload target catalog. When null the instance is a
/// read-only palette: [listTargets] derives ssh targets straight from
/// [sshProfileRepo] and never reads or writes `targets.json`.
class RuntimeTargetRegistry {
  RuntimeTargetRegistry({
    required SshProfileRepository sshProfileRepo,
    required this.isWindows,
    required this.isAndroid,
    TargetsRepository? repo,
    bool Function()? hasTermuxConfig,
  }) : _repo = repo,
       _sshProfileRepo = sshProfileRepo,
       _hasTermuxConfig = hasTermuxConfig;

  final TargetsRepository? _repo;
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
    final decodedId = RuntimeTargetId.decode(normalized);
    if (isWindows && decodedId is WslTargetId) {
      final distro = decodedId.distro;
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

  /// Merge persisted ssh targets with live profiles (add new, prune orphans;
  /// write back if changed) plus implicit local / wsl entries.
  ///
  /// When the catalog is empty — e.g. the home plane is unreachable and the
  /// workload catalog legitimately reads as empty — persisted targets are kept
  /// verbatim instead of being pruned as orphans, so an offline catalog can
  /// never wipe the local target list.
  Future<List<RuntimeTarget>> listTargets({String wslDistro = ''}) async {
    final profiles = await _sshProfileRepo.loadAll();
    final repo = _repo;

    final List<RuntimeTarget> reconciled;
    if (repo == null) {
      // Read-only palette: derive ssh targets directly from the source.
      reconciled = [
        for (final p in profiles) RuntimeTarget.ssh(p.id, label: p.name),
      ];
    } else {
      final file = await repo.load();
      if (profiles.isEmpty) {
        reconciled = List.of(file.targets);
      } else {
        final byId = {for (final p in profiles) p.id: p};
        final next = <RuntimeTarget>[];
        var changed = false;
        for (final t in file.targets) {
          final pid = t.sshProfileId;
          if (pid != null && byId.containsKey(pid)) {
            next.add(t.copyWith(label: byId[pid]!.name));
          } else {
            changed = true; // orphan dropped
          }
        }
        final existingPids = next
            .map((t) => t.sshProfileId)
            .whereType<String>()
            .toSet();
        for (final p in profiles) {
          if (!existingPids.contains(p.id)) {
            next.add(RuntimeTarget.ssh(p.id, label: p.name));
            changed = true;
          }
        }
        if (changed) {
          await repo.save(file.copyWith(targets: next));
        }
        reconciled = next;
      }
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
