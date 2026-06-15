import 'dart:convert';

import '../models/cli_preset.dart';
import '../services/io/filesystem.dart';
import '../utils/logger.dart';

class CliPresetsRepository {
  CliPresetsRepository({
    required this.fs,
    required this.presetsPath,
  });

  final Filesystem fs;
  final String presetsPath;

  Future<List<CliPreset>> load() async {
    try {
      final stat = await fs.stat(presetsPath);
      if (!stat.exists) return const [];

      final raw = await fs.readString(presetsPath);
      if (raw == null) return const [];

      final decoded = json.decode(raw);
      if (decoded is! List) return const [];

      return decoded
          .whereType<Map<String, Object?>>()
          .map((e) => CliPreset.fromJson(e))
          .toList(growable: false);
    } on Object catch (e) {
      appLogger.w('[cli-presets] load failed: $e');
      return const [];
    }
  }

  Future<List<CliPreset>> save(List<CliPreset> presets) async {
    try {
      final encoded = jsonEncode(presets.map((p) => p.toJson()).toList());
      await fs.writeString(presetsPath, encoded);
    } on Object catch (e) {
      appLogger.e('[cli-presets] save failed: $e');
    }
    return List.unmodifiable(presets);
  }
}
