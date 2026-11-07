import 'dart:convert';

import '../models/remote_target.dart';
import '../services/io/filesystem.dart';
import '../services/storage/storage_failure.dart';
import '../utils/logging/logger.dart';

/// Device-local catalog of remote connection targets.
///
/// A target is the bootstrap record needed to *reach* a machine: host, port,
/// user, auth type, and the vault entry that holds its credential. It never
/// lives on the remote home plane — otherwise a broken connection would take
/// away the very records needed to reconnect.
class RemoteTargetRepository {
  RemoteTargetRepository({required this.rootDir, required this.fs});

  final String rootDir;
  final Filesystem fs;

  String get _file => fs.pathContext.join(rootDir, 'remote-targets.json');

  String get _corruptFile =>
      fs.pathContext.join(rootDir, 'remote-targets.corrupt.json');

  Future<List<RemoteTarget>> loadAll() async {
    if (!(await fs.stat(_file)).isFile) return [];
    try {
      final raw = await fs.readString(_file);
      if (raw == null || raw.isEmpty) return [];
      final json = jsonDecode(raw);
      if (json is List) {
        return json
            .whereType<Map<String, Object?>>()
            .map(RemoteTarget.fromJson)
            .toList();
      }
    } on Object catch (error) {
      // A dropped transport must not read as "no targets stored": the user
      // would lose every connection entry on a flaky link.
      if (isStorageTransportFailure(error)) rethrow;
      AppLogger.instance.w(
        '[remote-targets] unreadable catalog at $_file; '
        'preserving original bytes as $_corruptFile',
        error: error,
      );
      await _preserveCorruptFile();
    }
    return [];
  }

  /// Moves an unparseable catalog aside so the next [saveAll] cannot overwrite
  /// the only copy of the user's targets. Best-effort: a failed rename must
  /// still let [loadAll] report "nothing stored".
  Future<void> _preserveCorruptFile() async {
    try {
      if (!(await fs.stat(_file)).isFile) return;
      await fs.rename(_file, _corruptFile);
    } on Object catch (error) {
      AppLogger.instance.w(
        '[remote-targets] failed to preserve unreadable catalog at $_file',
        error: error,
      );
    }
  }

  Future<void> saveAll(List<RemoteTarget> targets) async {
    await fs.ensureDir(rootDir);
    await fs.atomicWrite(
      _file,
      jsonEncode(targets.map((t) => t.toJson()).toList()),
    );
  }

  Future<void> save(RemoteTarget target) async {
    final all = await loadAll();
    final idx = all.indexWhere((t) => t.id == target.id);
    if (idx >= 0) {
      all[idx] = target;
    } else {
      all.add(target);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((t) => t.id == id);
    await saveAll(all);
  }

  Future<RemoteTarget?> findById(String id) async {
    for (final target in await loadAll()) {
      if (target.id == id) return target;
    }
    return null;
  }
}
