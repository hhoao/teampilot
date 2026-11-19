import 'dart:convert';

import '../models/connection/catalog_entry.dart';
import '../models/connection/machine_id.dart';
import '../models/ssh_profile.dart';
import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';
import '../services/storage/storage_failure.dart';
import '../utils/logging/logger.dart';

/// A read of the plane catalog. [legacyRows] is non-empty only while the file
/// still carries schema-1 address rows; `adoptCatalog` converts it.
final class CatalogSnapshot {
  const CatalogSnapshot({
    required this.entries,
    required this.legacyRows,
    required this.legacy,
  });

  final List<CatalogEntry> entries;
  final List<SshProfile> legacyRows;
  final bool legacy;
}

/// The home plane's machine catalog: membership and display names only.
///
/// Lives at `<home>/ssh_profiles/profiles.json`. It never stores an address, so
/// it can never be used to dial — the device-owned connection is the only
/// dialable record.
final class CatalogStore {
  CatalogStore({required HomeStorage storage})
    : _fs = storage.fs,
      _root = storage.paths.sshProfilesDir;

  static const int schemaVersion = 2;

  final Filesystem _fs;
  final String _root;

  String get path => _fs.pathContext.join(_root, 'profiles.json');

  /// Null means "the plane cannot be read"; callers treat that as unavailable.
  Future<CatalogSnapshot?> readSnapshot() async {
    final file = path;
    if (!(await _fs.stat(file)).isFile) {
      return const CatalogSnapshot(entries: [], legacyRows: [], legacy: false);
    }
    final String? raw;
    try {
      raw = await _fs.readString(file);
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
      return null;
    }
    if (raw == null || raw.isEmpty) {
      return const CatalogSnapshot(entries: [], legacyRows: [], legacy: false);
    }
    try {
      final json = jsonDecode(raw);
      if (json is Map && json['schemaVersion'] == schemaVersion) {
        final rows = json['entries'];
        return CatalogSnapshot(
          entries: rows is List
              ? rows
                    .whereType<Map<String, Object?>>()
                    .map(CatalogEntry.fromJson)
                    .toList()
              : const [],
          legacyRows: const [],
          legacy: false,
        );
      }
      if (json is List) {
        // Schema 1: full address rows. Kept in memory so adoption can seed a
        // device connection before the file is rewritten without them.
        return CatalogSnapshot(
          entries: [
            for (final row in json.whereType<Map<String, Object?>>())
              CatalogEntry(
                machineId: MachineId(row['id'] as String? ?? ''),
                displayName: row['name'] as String? ?? '',
                updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
              ),
          ],
          legacyRows: json
              .whereType<Map<String, Object?>>()
              .map(SshProfile.fromJson)
              .toList(),
          legacy: true,
        );
      }
    } on Object catch (error) {
      if (isStorageTransportFailure(error)) rethrow;
      AppLogger.instance.w(
        '[catalog] unreadable plane catalog at $file; treating as empty',
        error: error,
      );
    }
    return null;
  }

  Future<void> saveAll(List<CatalogEntry> entries) async {
    await _fs.ensureDir(_root);
    await _fs.atomicWrite(
      path,
      jsonEncode({
        'schemaVersion': schemaVersion,
        'entries': entries.map((entry) => entry.toJson()).toList(),
      }),
    );
  }

  Future<void> saveEntry(CatalogEntry entry) async {
    final entries = await _readEntriesOrAdoptFirst();
    if (entries == null) return;
    final next = [...entries];
    final index = next.indexWhere((e) => e.machineId == entry.machineId);
    if (index >= 0) {
      next[index] = entry;
    } else {
      next.add(entry);
    }
    await saveAll(next);
  }

  Future<void> delete(MachineId machineId) async {
    final entries = await _readEntriesOrAdoptFirst();
    if (entries == null) return;
    await saveAll(entries.where((e) => e.machineId != machineId).toList());
  }

  /// Writes are only issued for a v2 catalog: a legacy file must be adopted
  /// first, otherwise `saveAll` would silently drop its addresses.
  Future<List<CatalogEntry>?> _readEntriesOrAdoptFirst() async {
    final snapshot = await readSnapshot();
    if (snapshot == null || snapshot.legacy) return null;
    return snapshot.entries;
  }
}
