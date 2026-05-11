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
}
