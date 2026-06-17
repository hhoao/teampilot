import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves OpenCode XDG data paths (`$XDG_DATA_HOME/opencode/auth.json`).
final class OpencodeDataLayout {
  const OpencodeDataLayout();

  static const appDirName = 'opencode';
  static const authFileName = 'auth.json';
  static const isolatedDataDirName = 'xdg-data';

  String globalConfigHome(
    String homeDirectory, {
    Map<String, String> platformEnv = const {},
  }) {
    final home = homeDirectory.trim();
    final xdg =
        platformEnv['XDG_CONFIG_HOME']?.trim() ??
        Platform.environment['XDG_CONFIG_HOME']?.trim() ??
        '';
    if (xdg.isNotEmpty) {
      return p.join(xdg, appDirName);
    }
    if (Platform.isWindows) {
      final appData =
          platformEnv['APPDATA']?.trim() ??
          Platform.environment['APPDATA']?.trim() ??
          '';
      if (appData.isNotEmpty) {
        return p.join(appData, appDirName);
      }
    }
    return p.join(home, '.config', appDirName);
  }

  String opencodeConfigPath(String configHome) =>
      p.join(configHome, 'opencode.json');

  String globalDataHome(
    String homeDirectory, {
    Map<String, String> platformEnv = const {},
  }) {
    final home = homeDirectory.trim();
    final xdg =
        platformEnv['XDG_DATA_HOME']?.trim() ??
        Platform.environment['XDG_DATA_HOME']?.trim() ??
        '';
    if (xdg.isNotEmpty) {
      return p.join(xdg, appDirName);
    }
    if (Platform.isMacOS) {
      return p.join(
        home,
        'Library',
        'Application Support',
        appDirName,
      );
    }
    if (Platform.isWindows) {
      final appData =
          platformEnv['APPDATA']?.trim() ??
          Platform.environment['APPDATA']?.trim() ??
          '';
      if (appData.isNotEmpty) {
        return p.join(appData, appDirName);
      }
    }
    return p.join(home, '.local', 'share', appDirName);
  }

  String authJsonPath(String dataHome) => p.join(dataHome, authFileName);

  String providerXdgDataHome(String providerDir) =>
      p.join(providerDir, isolatedDataDirName);

  String providerDataHome(String providerDir) =>
      p.join(providerXdgDataHome(providerDir), appDirName);

  String providerAuthJsonPath(String providerDir) =>
      authJsonPath(providerDataHome(providerDir));
}
