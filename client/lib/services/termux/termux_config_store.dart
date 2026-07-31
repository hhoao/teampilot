import 'dart:convert';

import '../io/filesystem.dart';
import 'termux_config.dart';

class TermuxConfigStore {
  TermuxConfigStore({required this.rootDir, required Filesystem fs}) : _fs = fs;

  final String rootDir;
  final Filesystem _fs;

  String get _configDir => _fs.pathContext.join(rootDir, '.termux');

  String get _configFile => _fs.pathContext.join(_configDir, 'config.json');

  Future<TermuxConfig?> load() async {
    if (!(await _fs.stat(_configFile)).isFile) return null;
    try {
      final raw = await _fs.readString(_configFile);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      return TermuxConfig.fromJson(json);
    } on Object {
      return null;
    }
  }

  Future<void> save(TermuxConfig config) async {
    await _fs.ensureDir(_configDir);
    await _fs.atomicWrite(_configFile, jsonEncode(config.toJson()));
  }

  Future<void> clear() async {
    if ((await _fs.stat(_configFile)).exists) {
      await _fs.removeRecursive(_configFile);
    }
  }
}
