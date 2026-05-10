import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/layout_preferences.dart';

class LayoutRepository {
  const LayoutRepository(this._preferences);

  static const storageKey = 'flashskyai.layout.v1';

  final SharedPreferences _preferences;

  Future<LayoutPreferences> load() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return const LayoutPreferences();
    }

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return const LayoutPreferences();
      }
      return LayoutPreferences.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const LayoutPreferences();
    } on TypeError {
      return const LayoutPreferences();
    }
  }

  Future<void> save(LayoutPreferences preferences) async {
    await _preferences.setString(storageKey, jsonEncode(preferences.toJson()));
  }
}
