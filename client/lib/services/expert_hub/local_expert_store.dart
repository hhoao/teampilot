import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../models/discoverable_member.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists local expert records under `member-hub/local-templates/{key}.json`.
///
/// Keys map 1:1 to relative paths: user-created experts live under the
/// `local/` namespace (`local/{uuid}`); catalog clones are stored under their
/// catalog key (`acme/experts/pm`), so a clone shadows the catalog entry at
/// resolution ([LocalExpertStore.getByKey] reads any key).
class LocalExpertStore {
  LocalExpertStore({
    Filesystem? fs,
    String? dirOverride,
    String Function()? uuidFactory,
  }) : _fsOverride = fs,
       _dirOverride = dirOverride,
       _uuidFactory = uuidFactory ?? (() => const Uuid().v4());

  static const localKeyPrefix = 'local/';

  final Filesystem? _fsOverride;
  final String? _dirOverride;
  final String Function() _uuidFactory;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _dir =>
      _dirOverride ?? AppStorage.paths.memberHubLocalTemplatesDir;

  /// True when [key] is a user-created expert (`local/...`), as opposed to a
  /// catalog clone stored under its catalog key.
  static bool isLocalKey(String key) => key.startsWith(localKeyPrefix);

  static String idFromLocalKey(String key) =>
      key.substring(localKeyPrefix.length);

  String _pathForKey(String key) {
    final ctx = _fs.pathContext;
    return ctx.join(_dir, '$key.json');
  }

  /// Saves a user-created expert. Assigns `local/{uuid}` when [member.key] is
  /// not already a local key; always stamps [ExpertMemberSource.local].
  Future<DiscoverableMember> save(DiscoverableMember member) async {
    final id =
        isLocalKey(member.key) ? idFromLocalKey(member.key) : _uuidFactory();
    final saved = member.copyWith(
      key: '$localKeyPrefix$id',
      source: ExpertMemberSource.local,
      updatedAt: member.updatedAt != 0
          ? member.updatedAt
          : DateTime.now().millisecondsSinceEpoch,
    );
    await _writeUnderKey(saved);
    return saved;
  }

  /// Stores [member] under its own key verbatim (idempotent upsert). Used for
  /// catalog clones, whose key is the catalog key (shadowing the catalog).
  Future<DiscoverableMember> putClone(DiscoverableMember member) async {
    await _writeUnderKey(member);
    return member;
  }

  Future<void> _writeUnderKey(DiscoverableMember member) async {
    final path = _pathForKey(member.key);
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(path));
    await _fs.atomicWrite(path, jsonEncode(member.toJson()));
  }

  Future<List<DiscoverableMember>> loadAll() async {
    try {
      await _fs.ensureDir(_dir);
      final entries = await _fs.listDirRecursive(_dir);
      final members = <DiscoverableMember>[];
      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
        final path = _fs.pathContext.join(_dir, entry.name);
        try {
          final text = await _fs.readString(path);
          if (text == null || text.isEmpty) continue;
          members.add(
            DiscoverableMember.fromJson(
              (jsonDecode(text) as Map).cast<String, Object?>(),
            ),
          );
        } catch (_) {
          // Skip unreadable or invalid template files.
        }
      }
      return members;
    } catch (_) {
      return [];
    }
  }

  /// Removes the on-disk record for any [key].
  Future<void> delete(String key) async {
    try {
      await _fs.removeRecursive(_pathForKey(key));
    } catch (_) {
      // Best-effort delete.
    }
  }

  /// Shadow lookup: reads the record for [key] regardless of namespace.
  Future<DiscoverableMember?> getByKey(String key) async {
    try {
      final text = await _fs.readString(_pathForKey(key));
      if (text == null || text.isEmpty) return null;
      return DiscoverableMember.fromJson(
        (jsonDecode(text) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  /// One-time layout migration for the initial uuid-clone implementation.
  ///
  /// Scans legacy flat files at the store root: files carrying a non-empty
  /// `catalogKey` are the old uuid clones and are purged; the rest are legacy
  /// user-created experts, relocated under the `local/` namespace so
  /// [getByKey] still finds them. Idempotent.
  Future<void> migrateLegacyLayout() async {
    try {
      await _fs.ensureDir(_dir);
      final entries = await _fs.listDir(_dir);
      for (final entry in entries) {
        if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
        final path = _fs.pathContext.join(_dir, entry.name);
        try {
          final text = await _fs.readString(path);
          if (text == null || text.isEmpty) continue;
          final json = (jsonDecode(text) as Map).cast<String, Object?>();
          final catalogKey = json['catalogKey'];
          if (catalogKey is String && catalogKey.trim().isNotEmpty) {
            await _fs.removeRecursive(path); // old clone → purge
            continue;
          }
          final member = DiscoverableMember.fromJson(json);
          await _writeUnderKey(member); // relocate under its key namespace
          await _fs.removeRecursive(path);
        } catch (_) {
          // Skip unreadable files.
        }
      }
    } catch (_) {
      // Best-effort migration.
    }
  }
}
