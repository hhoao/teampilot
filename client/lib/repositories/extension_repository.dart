import 'dart:convert';

import '../models/extension_manifest.dart';
import '../models/extension_state.dart';
import '../services/io/filesystem.dart';

/// Owns `{teampilotRoot}/extensions/state.json`: install + enablement state.
class ExtensionRepository {
  ExtensionRepository({
    required Filesystem fs,
    required String stateFilePath,
    required List<ExtensionManifest> manifests,
  })  : _fs = fs,
        _stateFilePath = stateFilePath,
        _manifests = manifests;

  final Filesystem _fs;
  final String _stateFilePath;
  final List<ExtensionManifest> _manifests;

  ExtensionState? _cache;

  List<ExtensionManifest> get manifests => _manifests;

  Future<ExtensionState> load({bool forceReload = false}) async {
    if (!forceReload && _cache != null) return _cache!;
    final stat = await _fs.stat(_stateFilePath);
    if (!stat.exists) {
      return _cache = const ExtensionState();
    }
    final raw = await _fs.readString(_stateFilePath);
    if (raw == null || raw.trim().isEmpty) {
      return _cache = const ExtensionState();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return _cache =
            ExtensionState.fromJson(decoded.cast<String, Object?>());
      }
    } on Object {
      // Corrupt file → treat as empty; next save overwrites.
    }
    return _cache = const ExtensionState();
  }

  Future<void> save(ExtensionState state) async {
    _cache = state;
    final dir = _fs.pathContext.dirname(_stateFilePath);
    await _fs.ensureDir(dir);
    await _fs.atomicWrite(
      _stateFilePath,
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
  }

  Future<void> setGlobalEnabled(String id, bool enabled) async =>
      save((await load()).withGlobalEnabled(id, enabled));

  Future<void> setTeamOverride(String teamId, String id, bool? value) async =>
      save((await load()).withTeamOverride(teamId, id, value));

  Future<void> recordInstalled(String id, String version) async => save(
        (await load()).withInstalled(
          id,
          version,
          DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<void> recordUninstalled(String id) async =>
      save((await load()).withUninstalled(id));

  Future<bool> isEffectivelyEnabled(String teamId, String id) async =>
      (await load()).effectiveEnabled(teamId, id);

  /// Known extension ids that are effectively enabled for [teamId].
  Future<Set<String>> effectiveEnabledIds(String teamId) async {
    final state = await load();
    return {
      for (final manifest in _manifests)
        if (state.effectiveEnabled(teamId, manifest.id)) manifest.id,
    };
  }
}
