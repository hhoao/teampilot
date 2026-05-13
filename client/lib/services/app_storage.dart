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

  /// CLI's session history log.
  static String get cliHistoryPath => p.join(flashskyaiDataDir, 'history.jsonl');

  /// UI-owned local teams directory (under the Flutter sandbox).
  static String get teamsDir => p.join(basePath, 'teams');

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
  }
}
