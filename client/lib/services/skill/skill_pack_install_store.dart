import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Persists pack install exports under `skills/packs/<safeId>/install.json`.
class SkillPackInstallRecord {
  const SkillPackInstallRecord({
    required this.packId,
    required this.skillIds,
    required this.pathExports,
    required this.envExports,
    required this.installedAt,
    this.syncRoot,
  });

  final String packId;
  final List<String> skillIds;
  final List<String> pathExports;
  final Map<String, String> envExports;
  final int installedAt;
  final String? syncRoot;

  Map<String, Object?> toJson() => {
    'packId': packId,
    'skillIds': skillIds,
    'pathExports': pathExports,
    'envExports': envExports,
    'installedAt': installedAt,
    if (syncRoot != null && syncRoot!.isNotEmpty) 'syncRoot': syncRoot,
  };

  factory SkillPackInstallRecord.fromJson(Map<String, Object?> json) {
    final envRaw = json['envExports'];
    return SkillPackInstallRecord(
      packId: (json['packId'] as String?)?.trim() ?? '',
      skillIds: (json['skillIds'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
      pathExports: (json['pathExports'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false) ??
          const [],
      envExports: envRaw is Map
          ? {
              for (final e in envRaw.entries)
                e.key.toString(): e.value?.toString() ?? '',
            }
          : const {},
      installedAt: (json['installedAt'] as num?)?.toInt() ?? 0,
      syncRoot: (json['syncRoot'] as String?)?.trim(),
    );
  }
}

class SkillPackInstallStore {
  SkillPackInstallStore({Filesystem? fs, String? rootOverride})
    : _fsOverride = fs,
      _rootOverride = rootOverride;

  final Filesystem? _fsOverride;
  final String? _rootOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _root =>
      _rootOverride ?? AppStorage.paths.skillPacksInstallDir;

  static String safePackId(String packId) =>
      packId.trim().replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '__');

  String _recordPath(String packId) {
    final ctx = _fs.pathContext;
    return ctx.join(_root, safePackId(packId), 'install.json');
  }

  String packRootFor(String packId) {
    final ctx = _fs.pathContext;
    return ctx.join(_root, safePackId(packId));
  }

  Future<void> save(SkillPackInstallRecord record) async {
    final path = _recordPath(record.packId);
    final ctx = _fs.pathContext;
    await _fs.ensureDir(ctx.dirname(path));
    await _fs.atomicWrite(path, jsonEncode(record.toJson()));
  }

  Future<SkillPackInstallRecord?> load(String packId) async {
    try {
      final text = await _fs.readString(_recordPath(packId));
      if (text == null || text.isEmpty) return null;
      return SkillPackInstallRecord.fromJson(
        (jsonDecode(text) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<SkillPackInstallRecord>> loadAll() async {
    if (!(await _fs.stat(_root)).isDirectory) return const [];
    final out = <SkillPackInstallRecord>[];
    for (final entry in await _fs.listDir(_root)) {
      if (!entry.isDirectory) continue;
      final text = await _fs.readString(
        _fs.pathContext.join(_root, entry.name, 'install.json'),
      );
      if (text == null || text.isEmpty) continue;
      try {
        out.add(
          SkillPackInstallRecord.fromJson(
            (jsonDecode(text) as Map).cast<String, Object?>(),
          ),
        );
      } catch (_) {}
    }
    return out;
  }

  /// PATH segments for packs that own any of [skillIds].
  Future<List<String>> pathExportsForSkills(Iterable<String> skillIds) async {
    final wanted = skillIds.toSet();
    if (wanted.isEmpty) return const [];
    final out = <String>[];
    for (final record in await loadAll()) {
      final owns = record.skillIds.any(wanted.contains);
      if (!owns) continue;
      for (final p in record.pathExports) {
        if (p.isNotEmpty && !out.contains(p)) out.add(p);
      }
    }
    return out;
  }

  /// ENV exports for packs that own any of [skillIds].
  ///
  /// On key collision across packs, **first-wins** (earlier `loadAll` record
  /// keeps its value). Empty values are omitted.
  Future<Map<String, String>> envExportsForSkills(
    Iterable<String> skillIds,
  ) async {
    final wanted = skillIds.toSet();
    if (wanted.isEmpty) return const {};
    final out = <String, String>{};
    for (final record in await loadAll()) {
      final owns = record.skillIds.any(wanted.contains);
      if (!owns) continue;
      for (final e in record.envExports.entries) {
        final key = e.key.trim();
        final value = e.value;
        if (key.isEmpty || value.isEmpty) continue;
        out.putIfAbsent(key, () => value);
      }
    }
    return out;
  }

  /// Merges non-empty [exports] into [env] without wiping unrelated keys.
  static Map<String, String> mergeEnvExports(
    Map<String, String> env,
    Map<String, String> exports,
  ) {
    if (exports.isEmpty) return env;
    return {
      ...env,
      for (final e in exports.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };
  }

  /// Prepends [pathExports] onto [env]'s `PATH` (platform separator).
  static Map<String, String> prependPath(
    Map<String, String> env,
    List<String> pathExports, {
    String? platformPath,
    bool isWindows = false,
  }) {
    final extras = [
      for (final p in pathExports)
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (extras.isEmpty) return env;
    final sep = isWindows ? ';' : ':';
    final existing = env['PATH'] ?? platformPath ?? '';
    final merged = [
      ...extras,
      if (existing.trim().isNotEmpty) existing.trim(),
    ].join(sep);
    return {...env, 'PATH': merged};
  }
}
