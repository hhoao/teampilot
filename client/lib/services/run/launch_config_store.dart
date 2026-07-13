import 'dart:convert';

import '../../models/run/launch_config_document.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace_folder.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'shell_script_migrator.dart';

/// Read/write surface for per-folder `.teampilot/launch.json`.
///
/// [targetId] selects the owning folder's machine (local / WSL / SSH) so IO
/// routes through the matching [Filesystem] (same family as workspace shell).
abstract class LaunchConfigIo {
  Future<bool> exists(String path, {required String targetId});

  Future<String?> readString(String path, {required String targetId});

  Future<void> writeString(
    String path,
    String content, {
    required String targetId,
  });
}

/// In-memory [LaunchConfigIo] for unit tests (ignores [targetId]).
class MemoryLaunchConfigIo implements LaunchConfigIo {
  final Map<String, String> files = {};

  @override
  Future<bool> exists(String path, {required String targetId}) async =>
      files.containsKey(path);

  @override
  Future<String?> readString(String path, {required String targetId}) async =>
      files[path];

  @override
  Future<void> writeString(
    String path,
    String content, {
    required String targetId,
  }) async {
    files[path] = content;
  }
}

/// [LaunchConfigIo] backed by a single [Filesystem] (tests / local-only).
class FilesystemLaunchConfigIo implements LaunchConfigIo {
  FilesystemLaunchConfigIo(this._fs);

  final Filesystem _fs;

  @override
  Future<bool> exists(String path, {required String targetId}) async =>
      (await _fs.stat(path)).exists;

  @override
  Future<String?> readString(String path, {required String targetId}) =>
      _fs.readString(path);

  @override
  Future<void> writeString(
    String path,
    String content, {
    required String targetId,
  }) async {
    await _fs.ensureDir(_fs.pathContext.dirname(path));
    await _fs.writeString(path, content);
  }
}

/// Resolves a [Filesystem] for a workspace folder [targetId].
typedef LaunchConfigFilesystemResolver =
    Future<Filesystem> Function(String targetId);

/// Routes launch.json IO through each folder's [targetId] filesystem.
class TargetAwareLaunchConfigIo implements LaunchConfigIo {
  TargetAwareLaunchConfigIo({
    required LaunchConfigFilesystemResolver resolveFilesystem,
  }) : _resolveFilesystem = resolveFilesystem;

  final LaunchConfigFilesystemResolver _resolveFilesystem;

  /// Convenience: AppStorage home FS for local; inject resolver for WSL/SSH.
  factory TargetAwareLaunchConfigIo.localFallback({
    LaunchConfigFilesystemResolver? resolveFilesystem,
  }) {
    return TargetAwareLaunchConfigIo(
      resolveFilesystem:
          resolveFilesystem ??
          (targetId) async {
            if (targetId == WorkspaceFolder.localTargetId ||
                targetId.trim().isEmpty) {
              return AppStorage.fs;
            }
            throw StateError(
              'No filesystem resolver for launch.json targetId=$targetId',
            );
          },
    );
  }

  Future<Filesystem> _fsFor(String targetId) => _resolveFilesystem(targetId);

  @override
  Future<bool> exists(String path, {required String targetId}) async {
    final fs = await _fsFor(targetId);
    return (await fs.stat(path)).exists;
  }

  @override
  Future<String?> readString(String path, {required String targetId}) async {
    final fs = await _fsFor(targetId);
    return fs.readString(path);
  }

  @override
  Future<void> writeString(
    String path,
    String content, {
    required String targetId,
  }) async {
    final fs = await _fsFor(targetId);
    await fs.ensureDir(fs.pathContext.dirname(path));
    await fs.writeString(path, content);
  }
}

/// Reads, merges, and writes `.teampilot/launch.json` per workspace folder.
class LaunchConfigStore {
  LaunchConfigStore({required LaunchConfigIo io}) : _io = io;

  final LaunchConfigIo _io;

  LaunchConfigIo get io => _io;

  static String launchConfigPath(WorkspaceFolder folder) =>
      '${folder.path}/.teampilot/launch.json';

  Future<List<OwnedLaunchConfiguration>> listConfigurations({
    required List<WorkspaceFolder> folders,
  }) async {
    final results = <OwnedLaunchConfiguration>[];
    for (final folder in folders) {
      final doc = await _readDocument(folder);
      if (doc == null) continue;
      for (final config in doc.configurations) {
        results.add(
          OwnedLaunchConfiguration(owner: folder, configuration: config),
        );
      }
    }
    return results;
  }

  Future<List<OwnedLaunchCompound>> listCompounds({
    required List<WorkspaceFolder> folders,
  }) async {
    final results = <OwnedLaunchCompound>[];
    for (final folder in folders) {
      final doc = await _readDocument(folder);
      if (doc == null) continue;
      for (final compound in doc.compounds) {
        results.add(OwnedLaunchCompound(owner: folder, compound: compound));
      }
    }
    return results;
  }

  Future<void> upsertConfiguration({
    required WorkspaceFolder folder,
    required LaunchConfiguration configuration,
  }) async {
    final existing = await _readDocument(folder);
    final doc = existing ?? const LaunchConfigDocument(version: 1);
    final configs = [...doc.configurations];
    final index = configs.indexWhere((c) => c.id == configuration.id);
    if (index >= 0) {
      configs[index] = configuration;
    } else {
      configs.add(configuration);
    }
    await writeDocument(
      folder: folder,
      document: doc.copyWith(configurations: configs),
    );
  }

  Future<void> deleteConfiguration({
    required WorkspaceFolder folder,
    required String id,
  }) async {
    final existing = await _readDocument(folder);
    if (existing == null) return;
    final configs =
        existing.configurations.where((c) => c.id != id).toList();
    if (configs.length == existing.configurations.length) return;
    await writeDocument(
      folder: folder,
      document: existing.copyWith(configurations: configs),
    );
  }

  Future<void> writeDocument({
    required WorkspaceFolder folder,
    required LaunchConfigDocument document,
  }) async {
    final normalized = document.normalized();
    final path = launchConfigPath(folder);
    final json = const JsonEncoder.withIndent('  ').convert(normalized.toJson());
    await _io.writeString(path, json, targetId: folder.targetId);
  }

  Future<LaunchConfigDocument?> _readDocument(WorkspaceFolder folder) async {
    final path = launchConfigPath(folder);
    if (!await _io.exists(path, targetId: folder.targetId)) return null;
    final raw = await _io.readString(path, targetId: folder.targetId);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final json = Map<String, Object?>.from(decoded);
      final configs = json['configurations'];
      if (configs is List) {
        // Migrate legacy process → shellScript before model parse.
        json['configurations'] = [
          for (final item in configs)
            if (item is Map)
              ShellScriptMigrator.maybeMigrate(Map<String, Object?>.from(item))
            else
              item,
        ];
      }
      return LaunchConfigDocument.fromJson(json);
    } on FormatException {
      return null;
    }
  }
}

/// A compound tagged with the workspace folder that owns its `launch.json`.
class OwnedLaunchCompound {
  const OwnedLaunchCompound({required this.owner, required this.compound});

  final WorkspaceFolder owner;
  final LaunchCompound compound;

  String get compoundId => compound.id;

  /// Stable UI selection key: target + folder path + compound id.
  String get selectionKey =>
      '${owner.targetId}|${owner.path}|compound:${compound.id}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OwnedLaunchCompound &&
          runtimeType == other.runtimeType &&
          owner == other.owner &&
          compound == other.compound;

  @override
  int get hashCode => Object.hash(owner, compound);
}

extension on LaunchConfigDocument {
  LaunchConfigDocument copyWith({
    int? version,
    List<LaunchConfiguration>? configurations,
    List<LaunchCompound>? compounds,
  }) {
    return LaunchConfigDocument(
      version: version ?? this.version,
      configurations: configurations ?? this.configurations,
      compounds: compounds ?? this.compounds,
    );
  }
}
