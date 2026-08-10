import '../../registry/capabilities/history_context_env_capability.dart';

final class CursorHistoryContextEnv implements HistoryContextEnvCapability {
  const CursorHistoryContextEnv();
  @override
  Map<String, String> sessionEnv({String? toolRoot, String? home, String? userProfile}) {
    final env = <String, String>{};
    if (toolRoot != null && toolRoot.isNotEmpty) {
      env['CURSOR_CONFIG_DIR'] = toolRoot;
    }
    if (home != null && home.isNotEmpty) env['HOME'] = home;
    if (userProfile != null && userProfile.isNotEmpty) {
      env['USERPROFILE'] = userProfile;
    }
    return env;
  }
}
