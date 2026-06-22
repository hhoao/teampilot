import 'dart:convert';

import '../../models/runtime_target.dart';
import '../io/filesystem.dart';
import 'app_storage.dart';

/// On-disk shape of `targets.json` (control plane). Holds the authoritative
/// [defaultTargetId], the explicit WSL [wslDistro], and persisted ssh targets.
class TargetsRegistryFile {
  const TargetsRegistryFile({
    this.schemaVersion = 1,
    this.defaultTargetId = RuntimeTarget.localId,
    this.wslDistro = '',
    this.targets = const [],
  });

  final int schemaVersion;
  final String defaultTargetId;
  final String wslDistro;
  final List<RuntimeTarget> targets;

  factory TargetsRegistryFile.fromJson(Map<String, Object?> json) {
    final raw = json['targets'];
    return TargetsRegistryFile(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      defaultTargetId:
          json['defaultTargetId'] as String? ?? RuntimeTarget.localId,
      wslDistro: json['wslDistro'] as String? ?? '',
      targets: raw is List
          ? [
              for (final e in raw)
                if (e is Map<String, Object?>) RuntimeTarget.fromJson(e),
            ]
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'defaultTargetId': defaultTargetId,
    'wslDistro': wslDistro,
    'targets': targets.map((t) => t.toJson()).toList(),
  };

  TargetsRegistryFile copyWith({
    String? defaultTargetId,
    String? wslDistro,
    List<RuntimeTarget>? targets,
  }) => TargetsRegistryFile(
    schemaVersion: schemaVersion,
    defaultTargetId: defaultTargetId ?? this.defaultTargetId,
    wslDistro: wslDistro ?? this.wslDistro,
    targets: targets ?? this.targets,
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
}
