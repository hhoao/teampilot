import 'dart:convert';

import 'package:path/path.dart' as p;

import '../services/commands/command_catalog.dart';
import '../services/commands/key_chord.dart';
import '../services/io/filesystem.dart';
import '../services/storage/app_storage.dart';
import 'package:logger/logger.dart';
import '../utils/logging/logger.dart';

/// Persists user keybinding overrides at `{appDataRoot}/keybindings.json`.
///
/// On-disk shape: `{ "version": 1, "bindings": { "<commandId>": [chord...] } }`.
/// A missing command key means "use the catalog default"; an explicit empty
/// chord list means the command is intentionally unbound.
class KeybindingRepository {
  KeybindingRepository({Filesystem? fs, String? pathOverride})
    : _fsOverride = fs,
      _pathOverride = pathOverride;

  static const _version = 1;

  final Filesystem? _fsOverride;
  final String? _pathOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;
  String get _path =>
      _pathOverride ?? p.join(AppStorage.appDataRoot, 'keybindings.json');

  Future<Map<String, List<KeyChord>>> load() async {
    try {
      final raw = await _fs.readString(_path);
      if (raw == null || raw.trim().isEmpty) return {};

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final bindingsRaw = decoded['bindings'];
      if (bindingsRaw is! Map) return {};

      final knownIds = {for (final def in CommandCatalog.v1) def.id};
      final result = <String, List<KeyChord>>{};
      for (final entry in bindingsRaw.entries) {
        final commandId = entry.key.toString();
        if (!knownIds.contains(commandId)) continue;
        final chordsRaw = entry.value;
        if (chordsRaw is! List) continue;
        result[commandId] = chordsRaw
            .whereType<Map>()
            .map((raw) => KeyChord.fromJson(raw.cast<String, dynamic>()))
            .toList(growable: false);
      }
      return result;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[keybindings] load failed, resetting',
        error: error,
        stackTrace: stackTrace,
      );
      return {};
    }
  }

  Future<void> save(Map<String, List<KeyChord>> overrides) async {
    try {
      final ctx = _fs.pathContext;
      await _fs.ensureDir(ctx.dirname(_path));
      final payload = {
        'version': _version,
        'bindings': {
          for (final entry in overrides.entries)
            entry.key: entry.value.map((chord) => chord.toJson()).toList(),
        },
      };
      await _fs.atomicWrite(_path, jsonEncode(payload));
    } on Object catch (error, stackTrace) {
      appLogger.e(
        '[keybindings] save failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
