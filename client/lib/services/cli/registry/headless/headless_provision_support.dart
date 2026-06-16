import 'dart:convert';

import '../../../../repositories/app_provider_repository.dart';
import '../../../io/filesystem.dart';
import '../../../provider/config_profile_infrastructure.dart';
import '../../../provider/tool_config_generator.dart';
import '../../../storage/app_storage.dart';
import '../../../storage/runtime_layout.dart';

/// Shared storage-backed collaborators and JSON helpers for the per-CLI
/// [HeadlessProvisionCapability] implementations.
///
/// Everything is resolved lazily from [AppStorage] so the capabilities stay
/// `const` and registering them on a tool never touches storage. They are read
/// only inside `provision()`, after the runtime storage context is installed
/// (in tests, via `setUpTestAppStorage()`).
mixin HeadlessProvisionSupport {
  Filesystem get fs => AppStorage.fs;

  String get basePath => AppStorage.paths.basePath;

  AppProviderRepository get repository =>
      AppProviderRepository(basePath: basePath, fs: fs);

  ToolConfigGenerator get generator => const ToolConfigGenerator();

  ConfigProfileInfrastructure get profileInfra => ConfigProfileInfrastructure(
        basePath: basePath,
        layout: RuntimeLayout(teampilotRoot: basePath, fs: fs),
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
