import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract class AppSettingsRepository {
  Future<String?> loadLlmConfigPathOverride();
  Future<void> saveLlmConfigPathOverride(String? path);
}

class SharedPrefsAppSettingsRepository implements AppSettingsRepository {
  const SharedPrefsAppSettingsRepository(this._preferences);

  static const storageKey = 'flashskyai.app_settings.v1';
  static const _llmConfigPathKey = 'llmConfigPath';

  final SharedPreferences _preferences;

  @override
  Future<String?> loadLlmConfigPathOverride() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final value = decoded[_llmConfigPathKey];
      if (value is String && value.isNotEmpty) return value;
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveLlmConfigPathOverride(String? path) async {
    final current = _readMap();
    if (path == null || path.trim().isEmpty) {
      current.remove(_llmConfigPathKey);
    } else {
      current[_llmConfigPathKey] = path;
    }
    if (current.isEmpty) {
      await _preferences.remove(storageKey);
    } else {
      await _preferences.setString(storageKey, jsonEncode(current));
    }
  }

  Map<String, Object?> _readMap() {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) return <String, Object?>{};
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return <String, Object?>{};
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return <String, Object?>{};
    }
  }
}

/// Test-friendly in-memory implementation.
class InMemoryAppSettingsRepository implements AppSettingsRepository {
  InMemoryAppSettingsRepository({String? llmConfigPathOverride})
      : _llmConfigPathOverride = llmConfigPathOverride;

  String? _llmConfigPathOverride;

  @override
  Future<String?> loadLlmConfigPathOverride() async => _llmConfigPathOverride;

  @override
  Future<void> saveLlmConfigPathOverride(String? path) async {
    final trimmed = path?.trim();
    _llmConfigPathOverride =
        (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
