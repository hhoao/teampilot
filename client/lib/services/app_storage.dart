import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorage {
  AppStorage._();

  static String? _basePath;

  static String get basePath => _basePath ?? '.';

  /// Root of the CLI-owned data directory (`~/.flashskyai`). Shared with the
  /// `flashskyai` CLI: sessions, history, and the canonical team configs all
  /// live under here.
  static String get flashskyaiDataDir => p.join(
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '',
    '.flashskyai',
  );

  /// CLI's `teams/` directory. UI imports from here on startup.
  static String get cliTeamsDir => p.join(flashskyaiDataDir, 'teams');

  /// CLI's active session descriptors (`sessions/<uuid>.json`).
  static String get cliSessionsDir => p.join(flashskyaiDataDir, 'sessions');

  /// True when the CLI has written `sessions/<sessionId>.json` under [cliSessionsDir].
  ///
  /// If the UI marks a session as launched but the user never produced CLI-side
  /// session state (e.g. no messages), `--resume` can fail while `--session-id`
  /// still works. Use this to pick resume vs fixed id.
  static bool cliSessionDescriptorExists(String sessionId) {
    final id = sessionId.trim();
    if (id.isEmpty) return false;
    return File(p.join(cliSessionsDir, '$id.json')).existsSync();
  }

  /// CLI's session history log (legacy). Session metadata lives in [appProjectsDir];
  /// do not use this path for app-owned session state.
  @Deprecated('Use appProjectsDir + SessionRepository; CLI history is not the session index.')
  static String get cliHistoryPath => p.join(flashskyaiDataDir, 'history.jsonl');

  /// UI-owned local teams directory (under the Flutter sandbox).
  static String get teamsDir => p.join(basePath, 'teams');

  /// App-owned project/session metadata (`projects.json` + `sessions/`).
  static String get appProjectsDir => p.join(basePath, 'projects');

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
  }
}
