import 'dart:convert';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../../models/team_generation_settings.dart';

final class TeamGenerationSettingsStore {
  TeamGenerationSettingsStore({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? AppStorage.paths.teamGenerationSettingsJson;

  Future<TeamGenerationSettings> load() async {
    try {
      final raw = await _fs.readString(_path);
      if (raw == null || raw.trim().isEmpty) {
        return TeamGenerationSettings();
      }
      return TeamGenerationSettings.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on Object {
      return TeamGenerationSettings();
    }
  }

  Future<void> save(TeamGenerationSettings settings) async {
    final normalized = settings.normalized();
    await _fs.ensureDir(_fs.pathContext.dirname(_path));
    await _fs.atomicWrite(
      _path,
      const JsonEncoder.withIndent('  ').convert(normalized.toJson()),
    );
  }
}
