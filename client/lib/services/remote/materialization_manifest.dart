import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../io/filesystem.dart';

/// Records the content hash of each materialized path under a work machine root
/// (`<machineRoot>/.materialized.json`) so [WorkMachineMaterializer] can skip
/// re-copying unchanged subtrees on later reconciles (P3c §3.3.5, build-cache
/// semantics). fs is injected → unit-testable without real SFTP.
class MaterializationManifest {
  MaterializationManifest({required this.fs, required this.machineRoot});

  final Filesystem fs;
  final String machineRoot;

  String get _file => fs.pathContext.join(machineRoot, '.materialized.json');

  /// Map of relative path → content hash. Empty when no manifest exists yet.
  Future<Map<String, String>> load() async {
    try {
      final raw = await fs.readString(_file);
      if (raw == null || raw.isEmpty) return {};
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) {
        return {for (final e in json.entries) e.key: '${e.value}'};
      }
    } on Object {
      // fall through to empty
    }
    return {};
  }

  Future<void> save(Map<String, String> hashes) async {
    await fs.ensureDir(machineRoot);
    await fs.atomicWrite(_file, jsonEncode(hashes));
  }

  /// Stable content hash (sha256 hex) of [bytes].
  String hashOf(List<int> bytes) => sha256.convert(bytes).toString();
}
