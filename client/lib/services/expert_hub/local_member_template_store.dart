import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../models/discoverable_member.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists user-saved expert templates under `member-hub/local-templates/*.json`.
class LocalMemberTemplateStore {
  LocalMemberTemplateStore({
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

  static bool isLocalKey(String key) => key.startsWith(localKeyPrefix);

  static String idFromLocalKey(String key) =>
      key.substring(localKeyPrefix.length);

  String _pathForId(String id) {
    final ctx = _fs.pathContext;
    return ctx.join(_dir, '$id.json');
  }

  String _pathForKey(String key) => _pathForId(idFromLocalKey(key));

  /// Writes [member] to disk. Assigns `local/{uuid}` when [member.key] is not
  /// already a local key; always stamps [ExpertMemberSource.local].
  Future<DiscoverableMember> save(DiscoverableMember member) async {
    final id = isLocalKey(member.key) ? idFromLocalKey(member.key) : _uuidFactory();
    final saved = DiscoverableMember(
      key: '$localKeyPrefix$id',
      name: member.name,
      description: member.description,
      category: member.category,
      author: member.author,
      updatedAt: member.updatedAt != 0
          ? member.updatedAt
          : DateTime.now().millisecondsSinceEpoch,
      tags: member.tags,
      member: member.member,
      skillDeps: member.skillDeps,
      source: ExpertMemberSource.local,
      originTeamKey: member.originTeamKey,
    );
    await _fs.ensureDir(_dir);
    await _fs.atomicWrite(
      _pathForId(id),
      jsonEncode(saved.toJson()),
    );
    return saved;
  }

  Future<List<DiscoverableMember>> loadAll() async {
    try {
      await _fs.ensureDir(_dir);
      final entries = await _fs.listDir(_dir);
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

  /// Removes the on-disk template when [key] starts with `local/`.
  Future<void> delete(String key) async {
    if (!isLocalKey(key)) return;
    try {
      await _fs.removeRecursive(_pathForKey(key));
    } catch (_) {
      // Best-effort delete.
    }
  }

  Future<DiscoverableMember?> getByKey(String key) async {
    if (!isLocalKey(key)) return null;
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
}
