import 'dart:convert';

import '../../models/plugin.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Loads the installed-plugin catalog (`plugins/plugins.json`) — the single
/// source plugin provisioners use to map enabled plugin ids to bundles.
abstract final class InstalledPluginCatalog {
  InstalledPluginCatalog._();

  static Future<List<Plugin>> load(Filesystem fs, String teampilotRoot) async {
    final path = AppPaths.pluginsJsonForTeampilotRoot(teampilotRoot);
    final text = await fs.readString(path);
    if (text == null || text.trim().isEmpty) return const [];
    try {
      final root = (jsonDecode(text) as Map).cast<String, Object?>();
      return (root['plugins'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => Plugin.fromJson(m.cast<String, Object?>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}
