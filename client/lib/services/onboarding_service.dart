import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/app_settings_repository.dart';
import '../repositories/session_preferences_repository.dart';
import 'app_storage.dart';
import 'io/filesystem.dart';
import 'runtime_storage_context.dart';

/// Decides whether the first-run setup wizard should appear and migrates legacy
/// installs that already have app data.
class OnboardingService {
  OnboardingService({
    required AppSettingsRepository appSettings,
    required SharedPreferences preferences,
    Filesystem? fs,
  }) : _appSettings = appSettings,
       _preferences = preferences,
       _fs = fs ?? AppStorage.fs;

  final AppSettingsRepository _appSettings;
  final SharedPreferences _preferences;
  final Filesystem _fs;

  Future<bool> shouldShowOnboarding() async {
    if (await _hasLegacyAppData()) {
      await _appSettings.saveHasCompletedOnboarding(true);
      return false;
    }
    return !(await _appSettings.loadHasCompletedOnboarding());
  }

  Future<bool> _hasLegacyAppData() async {
    if (_preferences.containsKey(SessionPreferencesRepository.storageKey)) {
      return true;
    }
    if (!RuntimeStorageContext.isInstalled) return false;

    if (await _dirHasEntries(AppStorage.paths.teamsDir)) return true;
    if (await _dirHasEntries(AppStorage.paths.providerConfigDir)) return true;

    final legacyProvidersFile = AppStorage.paths.providerConfigFile;
    if ((await _fs.stat(legacyProvidersFile)).isFile) return true;

    return false;
  }

  Future<bool> _dirHasEntries(String path) async {
    final stat = await _fs.stat(path);
    if (!stat.isDirectory) return false;
    final entries = await _fs.listDir(path);
    return entries.isNotEmpty;
  }
}
