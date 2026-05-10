import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/team_config.dart';

class TeamRepository {
  const TeamRepository(this._preferences);

  static const storageKey = 'flashskyai.teams.v1';

  final SharedPreferences _preferences;

  Future<List<TeamConfig>> loadTeams() async {
    final stored = _preferences.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return [];
    }

    try {
      final decoded = jsonDecode(stored);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map>()
          .map((item) => TeamConfig.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false);
    } on FormatException {
      return [];
    } on TypeError {
      return [];
    }
  }

  Future<void> saveTeams(List<TeamConfig> teams) async {
    final encoded = jsonEncode(teams.map((team) => team.toJson()).toList());
    await _preferences.setString(storageKey, encoded);
  }
}
