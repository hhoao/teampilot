import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppStorage {
  AppStorage._();

  static String? _basePath;

  static String get basePath => _basePath ?? '.';

  static String get flashskyaiDir => p.join(basePath, 'flashskyai');

  static String get teamsDir => p.join(flashskyaiDir, 'teams');

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _basePath = dir.path;
  }

  static Future<void> clearTeams() async {
    try {
      final dir = Directory(teamsDir);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on Object {
      // best effort
    }
  }
}
