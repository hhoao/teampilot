import '../../models/connection_mode.dart';
import '../../models/runtime_target.dart';
import '../../models/windows_storage_backend.dart';
import '../../repositories/ssh_profile_repository.dart';
import 'targets_repository.dart';

/// Single source of truth that folds the four legacy runtime knobs (storage
/// backend, connection mode, active ssh profile, WSL distro) into a list of
/// [RuntimeTarget]s plus an authoritative `defaultTargetId`. P0: one default
/// target reproduces today's behavior.
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

  /// One-time: build targets.json from legacy sources when it does not exist.
  Future<void> migrateIfNeeded({
    required ConnectionMode legacyMode,
    required WindowsStorageBackend legacyBackend,
    required String? parsedWslDistro,
  }) async {
    if (await _repo.exists()) return;
    final profiles = await _sshProfileRepo.loadAll();
    final selected = await _sshProfileRepo.loadSelectedProfileId();
    final distro = (parsedWslDistro ?? '').trim();

    final sshTargets = [
      for (final p in profiles) RuntimeTarget.ssh(p.id, label: p.name),
    ];

    String defaultId;
    if (legacyMode == ConnectionMode.ssh &&
        selected.isNotEmpty &&
        profiles.any((p) => p.id == selected)) {
      defaultId = 'ssh:$selected';
    } else if (isWindows &&
        legacyBackend == WindowsStorageBackend.wsl &&
        distro.isNotEmpty) {
      defaultId = 'wsl:$distro';
    } else if (isAndroid && sshTargets.isNotEmpty) {
      defaultId = sshTargets.first.id;
    } else {
      defaultId = RuntimeTarget.localId;
    }

    await _repo.save(
      TargetsRegistryFile(
        defaultTargetId: defaultId,
        wslDistro: distro,
        targets: sshTargets,
      ),
    );
  }

  Future<String> wslDistro() async => (await _repo.load()).wslDistro;

  /// Merge persisted ssh targets with live ssh_profiles (add new, prune orphans;
  /// write back if changed) plus implicit local / wsl entries.
  Future<List<RuntimeTarget>> listTargets() async {
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
      if (isWindows && file.wslDistro.trim().isNotEmpty)
        RuntimeTarget.wsl(file.wslDistro.trim()),
      ...reconciled,
    ];
  }

  Future<RuntimeTarget> defaultTarget() async {
    final file = await _repo.load();
    final all = await listTargets();
    return all.firstWhere(
      (t) => t.id == file.defaultTargetId,
      orElse: RuntimeTarget.local,
    );
  }

  Future<void> setDefaultTargetId(String id) async {
    final file = await _repo.load();
    await _repo.save(file.copyWith(defaultTargetId: id));
  }
}
