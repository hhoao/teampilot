import 'dart:convert';

import '../../models/run/launch_config_document.dart';
import '../../models/run/launch_configuration.dart';
import '../../models/workspace_folder.dart';

/// Local read/write surface for per-folder `.teampilot/launch.json`.
///
/// v1 uses in-memory or host filesystem only. Production wiring will route
/// through each [WorkspaceFolder.targetId] (WSL/SSH) in a later task.
abstract class LaunchConfigIo {
  Future<bool> exists(String path);

  Future<String?> readString(String path);

  Future<void> writeString(String path, String content);
}

/// In-memory [LaunchConfigIo] for unit tests.
class MemoryLaunchConfigIo implements LaunchConfigIo {
  final Map<String, String> files = {};

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<String?> readString(String path) async => files[path];

  @override
  Future<void> writeString(String path, String content) async {
    files[path] = content;
  }
}

/// Reads, merges, and writes `.teampilot/launch.json` per workspace folder.
class LaunchConfigStore {
  LaunchConfigStore({required LaunchConfigIo io}) : _io = io;

  final LaunchConfigIo _io;

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

  Future<void> writeDocument({
    required WorkspaceFolder folder,
    required LaunchConfigDocument document,
  }) async {
    final normalized = document.normalized();
    final path = launchConfigPath(folder);
    final json = const JsonEncoder.withIndent('  ').convert(normalized.toJson());
    await _io.writeString(path, json);
  }

  Future<LaunchConfigDocument?> _readDocument(WorkspaceFolder folder) async {
    final path = launchConfigPath(folder);
    if (!await _io.exists(path)) return null;
    final raw = await _io.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
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
