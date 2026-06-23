import 'package:shared_preferences/shared_preferences.dart';

/// Device-local authority for the home target (the machine the control plane
/// runs on). Readable before any runtime context is installed — this is the
/// only place the home identity can live (the control plane is ON the home
/// machine; on Android that is the remote we cannot reach until we know it).
class HomeTargetStore {
  const HomeTargetStore(this._prefs);
  static const _key = 'flashskyai.home_target.v1';
  final SharedPreferences _prefs;

  /// '' means unset — caller applies the platform default (see app_shell).
  String load() => _prefs.getString(_key)?.trim() ?? '';

  Future<void> save(String id) async => _prefs.setString(_key, id.trim());
}
