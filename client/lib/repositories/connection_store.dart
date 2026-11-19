import 'dart:convert';

import '../models/connection/device_connection.dart';
import '../models/connection/machine_id.dart';
import '../services/io/filesystem.dart';
import '../services/storage/storage_failure.dart';
import '../utils/logging/logger.dart';

/// The catalog on disk is not in the schema this build writes. Upgrade it with
/// `ConnectionBootstrap`; never guess an address set from an old shape.
final class StaleConnectionCatalog implements Exception {
  const StaleConnectionCatalog(this.message);
  final String message;
  @override
  String toString() => 'StaleConnectionCatalog($message)';
}

/// Device-local store of this device's connections.
///
/// A connection is the only record that may be dialed: it owns the address set,
/// the account, the credential reference and the trust pins. It never lives on
/// the home plane — a broken home connection must not take away the records
/// needed to reconnect.
final class ConnectionStore {
  ConnectionStore({required this.rootDir, required this.fs});

  static const int schemaVersion = 2;

  final String rootDir;
  final Filesystem fs;

  String get file => fs.pathContext.join(rootDir, 'remote-targets.json');

  String get _corruptFile =>
      fs.pathContext.join(rootDir, 'remote-targets.corrupt.json');

  Future<List<DeviceConnection>> loadAll() async {
    final raw = await _read();
    if (raw == null || raw.isEmpty) return [];
    try {
      final json = jsonDecode(raw);
      final version = json is Map ? json['schemaVersion'] : null;
      if (version != schemaVersion) {
        throw StaleConnectionCatalog(
          '$file is schema ${version ?? 1}, expected $schemaVersion',
        );
      }
      final rows = json is Map ? json['connections'] : null;
      if (rows is! List) return [];
      return rows
          .whereType<Map<String, Object?>>()
          .map(DeviceConnection.fromJson)
          .toList();
    } on StaleConnectionCatalog {
      rethrow;
    } on Object catch (error) {
      // A dropped transport must not read as "no connections stored": the user
      // would lose every entry on a flaky link.
      if (isStorageTransportFailure(error)) rethrow;
      AppLogger.instance.w(
        '[connections] unreadable catalog at $file; '
        'preserving original bytes as $_corruptFile',
        error: error,
      );
      await _preserveCorruptFile();
      return [];
    }
  }

  Future<String?> _read() async {
    if (!(await fs.stat(file)).isFile) return null;
    try {
      return await fs.readString(file);
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
      return null;
    }
  }

  /// Moves an unparseable catalog aside so the next [saveAll] cannot overwrite
  /// the only copy of the user's connections.
  Future<void> _preserveCorruptFile() async {
    try {
      if (!(await fs.stat(file)).isFile) return;
      await fs.rename(file, _corruptFile);
    } on Object catch (error) {
      AppLogger.instance.w(
        '[connections] failed to preserve unreadable catalog at $file',
        error: error,
      );
    }
  }

  Future<void> saveAll(List<DeviceConnection> connections) async {
    await fs.ensureDir(rootDir);
    await fs.atomicWrite(
      file,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'connections': connections.map((c) => c.toJson()).toList(),
      }),
    );
  }

  Future<void> save(DeviceConnection connection) async {
    final all = await loadAll();
    final index = all.indexWhere((c) => c.machineId == connection.machineId);
    if (index >= 0) {
      all[index] = connection;
    } else {
      all.add(connection);
    }
    await saveAll(all);
  }

  Future<void> delete(MachineId machineId) async {
    final all = await loadAll();
    all.removeWhere((c) => c.machineId == machineId);
    await saveAll(all);
  }

  Future<DeviceConnection?> findById(MachineId machineId) async {
    for (final connection in await loadAll()) {
      if (connection.machineId == machineId) return connection;
    }
    return null;
  }
}
