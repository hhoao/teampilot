import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_preferences.dart';

class SessionPreferencesRepository {
  const SessionPreferencesRepository(this._preferences);

  static const storageKey = 'flashskyai.session_preferences.v1';

  final SharedPreferences _preferences;

  Future<SessionPreferences> load() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return const SessionPreferences();
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        return const SessionPreferences();
      }
      return SessionPreferences.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return const SessionPreferences();
    } on TypeError {
      return const SessionPreferences();
    }
  }

  Future<void> save(SessionPreferences preferences) async {
    await _preferences.setString(storageKey, jsonEncode(preferences.toJson()));
  }
}
