import 'dart:convert';

import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../provider/config_profile_infrastructure.dart';
import '../../../provider/tool_config_generator.dart';
import '../../../storage/home_storage.dart';
import '../../../storage/runtime_layout.dart';

/// Shared storage-backed collaborators and JSON helpers for the per-CLI
/// [HeadlessCapability] implementations.
///
/// Implementers expose the injected home storage via [storage]; the registry
/// threads a [HomeStorage] into each capability at construction time
/// (`CliBootstrap.storage`, wired in the app shell after the home context is
/// bound). Capabilities default to `const` construction with `storage == null`
/// — that is only valid for launch-arg assembly; `provision()` touches the
/// home plane and throws when no storage was injected (matching the legacy
/// behavior of an unbound storage global).
mixin HeadlessProvisionSupport {
  /// Home control-plane storage injected at registry construction.
  HomeStorage? get storage;

  /// Tolerant like the other capabilities: default-registered capabilities
  /// (registry built without a `CliBootstrap`, i.e. tests and arg-assembly
  /// only use) fall back to the native default instead of throwing —
  /// production always configures the registry with real storage.
  HomeStorage get _home => storage ?? HomeStorage.nativeDefault();

  Filesystem get fs => _home.fs;

  String get basePath => _home.paths.basePath;

  String get home => _home.home;

  AppProviderRepository get repository =>
      AppProviderRepository(basePath: basePath, fs: fs, storage: _home);

  ToolConfigGenerator get generator => const ToolConfigGenerator();

  ConfigProfileInfrastructure get profileInfra => ConfigProfileInfrastructure(
    basePath: basePath,
    layout: RuntimeLayout(teampilotRoot: basePath, fs: fs),
    storage: _home,
    fs: fs,
  );

  Future<void> writeJson(String path, Map<String, Object?> value) async {
    await fs.atomicWrite(
      path,
      const JsonEncoder.withIndent('  ').convert(value),
    );
  }

  Future<Map<String, Object?>> readJsonMap(String path) async {
    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on FormatException {
      // Fall through to empty map.
    }
    return <String, Object?>{};
  }
}
