import 'dart:convert';

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import 'app_storage.dart';

/// On-disk shape of `targets.json` (control plane). A pure target catalog —
/// the home target authority lives device-local in [HomeTargetStore], not here.
class TargetsRegistryFile {
  const TargetsRegistryFile({
    this.schemaVersion = 1,
    this.targets = const [],
    this.credentialOptIn = const [],
    this.installOptOut = const [],
    this.cliPathOverrides = const {},
  });

  final int schemaVersion;
  final List<RuntimeTarget> targets;

  /// P3c: target ids the user explicitly opted in to credential push (default
  /// empty = no key materialized to any remote). Consent is config, not part of
  /// the [RuntimeTarget] runtime identity.
  final List<String> credentialOptIn;

  /// P3c: target ids where remote CLI auto-install is disabled (default empty =
  /// auto-install is on for every target after locate fails).
  final List<String> installOptOut;

  /// P3c: per-target manual CLI path overrides — `targetId → {cliValue → path}`
  /// (manual bottom-fill when remote locate/install can't resolve a CLI).
  final Map<String, Map<String, String>> cliPathOverrides;

  factory TargetsRegistryFile.fromJson(Map<String, Object?> json) {
    final raw = json['targets'];
    final optIn = json['credentialOptIn'];
    final installOptOut = json['installOptOut'];
    final overrides = json['cliPathOverrides'];
    return TargetsRegistryFile(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      targets: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, Object?>) RuntimeTarget.fromJson(e),
            ]
          : const [],
      credentialOptIn: optIn is List
          ? [for (final e in optIn) '$e'].where((s) => s.isNotEmpty).toList()
          : const [],
      installOptOut: installOptOut is List
          ? [
              for (final e in installOptOut)
                '$e',
            ].where((s) => s.isNotEmpty).toList()
          : const [],
      cliPathOverrides: overrides is Map<String, Object?>
          ? {
              for (final e in overrides.entries)
                if (e.value is Map<String, Object?>)
                  e.key: {
                    for (final c in (e.value as Map<String, Object?>).entries)
                      c.key: '${c.value}',
                  },
            }
          : const {},
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'targets': targets.map((t) => t.toJson()).toList(),
    if (credentialOptIn.isNotEmpty) 'credentialOptIn': credentialOptIn,
    if (installOptOut.isNotEmpty) 'installOptOut': installOptOut,
    if (cliPathOverrides.isNotEmpty) 'cliPathOverrides': cliPathOverrides,
  };

  TargetsRegistryFile copyWith({
    List<RuntimeTarget>? targets,
    List<String>? credentialOptIn,
    List<String>? installOptOut,
    Map<String, Map<String, String>>? cliPathOverrides,
  }) =>
      TargetsRegistryFile(
        schemaVersion: schemaVersion,
        targets: targets ?? this.targets,
        credentialOptIn: credentialOptIn ?? this.credentialOptIn,
        installOptOut: installOptOut ?? this.installOptOut,
        cliPathOverrides: cliPathOverrides ?? this.cliPathOverrides,
      );
}

/// Reads/writes `targets.json`. Mirrors [SshProfileRepository]'s injection
/// pattern (constructor `rootDir`/`fs` overrides for tests).
class TargetsRepository {
  TargetsRepository({String? rootDir, Filesystem? fs})
    : _rootOverride = rootDir,
      _fsOverride = fs;

  final String? _rootOverride;
  final Filesystem? _fsOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _file => _rootOverride != null
      ? _fs.pathContext.join(_rootOverride, 'targets.json')
      : AppStorage.paths.targetsFile;

  Future<bool> exists() async => (await _fs.stat(_file)).isFile;

  Future<TargetsRegistryFile> load() async {
    if (!await exists()) return const TargetsRegistryFile();
    try {
      final raw = await _fs.readString(_file);
      if (raw == null || raw.isEmpty) return const TargetsRegistryFile();
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return TargetsRegistryFile.fromJson(json);
      }
    } on Object {
      // fall through to defaults
    }
    return const TargetsRegistryFile();
  }

  Future<void> save(TargetsRegistryFile file) async {
    final dir = _fs.pathContext.dirname(_file);
    await _fs.ensureDir(dir);
    await _fs.atomicWrite(_file, jsonEncode(file.toJson()));
  }

  // ── P3c: credential-push opt-in (default off) ──────────────────────────────

  Future<bool> isCredentialOptIn(String targetId) async =>
      (await load()).credentialOptIn.contains(targetId);

  Future<void> setCredentialOptIn(String targetId, bool optIn) async {
    final file = await load();
    final next = file.credentialOptIn.toSet();
    if (optIn) {
      next.add(targetId);
    } else {
      next.remove(targetId);
    }
    await save(file.copyWith(credentialOptIn: (next.toList()..sort())));
  }

  Future<bool> isInstallOptIn(String targetId) async =>
      !(await load()).installOptOut.contains(targetId);

  Future<void> setInstallOptIn(String targetId, bool optIn) async {
    final file = await load();
    final next = file.installOptOut.toSet();
    if (optIn) {
      next.remove(targetId);
    } else {
      next.add(targetId);
    }
    await save(file.copyWith(installOptOut: (next.toList()..sort())));
  }

  // ── P3c: per-target manual CLI path override ───────────────────────────────

  Future<String?> cliPathOverride(String targetId, String cliValue) async =>
      (await load()).cliPathOverrides[targetId]?[cliValue];

  Future<void> setCliPathOverride(
    String targetId,
    String cliValue,
    String path,
  ) async {
    final file = await load();
    final overrides = {
      for (final e in file.cliPathOverrides.entries)
        e.key: {...e.value},
    };
    final forTarget = overrides.putIfAbsent(targetId, () => {});
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      forTarget.remove(cliValue);
      if (forTarget.isEmpty) overrides.remove(targetId);
    } else {
      forTarget[cliValue] = trimmed;
    }
    await save(file.copyWith(cliPathOverrides: overrides));
  }
}
