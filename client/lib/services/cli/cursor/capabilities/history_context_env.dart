import 'package:path/path.dart' as p;

import '../../registry/capabilities/history_context_env_capability.dart';

/// Cursor isolates a fake `$HOME` whose parent of the session CONFIG_DIR
/// (`<toolDir>/home`) is the session's history home.
final class CursorHistoryContextEnv implements HistoryContextEnvCapability {
  const CursorHistoryContextEnv();
  @override
  Map<String, String> sessionEnv({String? toolRoot}) {
    final env = <String, String>{};
    if (toolRoot != null && toolRoot.isNotEmpty) {
      env['CURSOR_CONFIG_DIR'] = toolRoot;
      final home = p.dirname(toolRoot);
      env['HOME'] = home;
      env['USERPROFILE'] = home;
    }
    return env;
  }
}
