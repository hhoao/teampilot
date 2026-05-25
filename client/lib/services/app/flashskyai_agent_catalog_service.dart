import 'package:flutter/foundation.dart';
import '../storage/app_storage.dart';
import '../cli/cli_data_layout.dart';
import '../io/filesystem.dart';
import '../storage/flashskyai_storage_roots.dart';

/// Built-in `--agent` ids (subset of `flashskyai agents` / CLI presets).
@immutable
class FlashskyaiBuiltinAgentEntry {
  const FlashskyaiBuiltinAgentEntry({
    required this.id,
    required this.modelHintEn,
    required this.modelHintZh,
  });

  final String id;
  final String modelHintEn;
  final String modelHintZh;
}

/// Built-in presets and dropdown helpers for member `--agent` selection.
abstract final class FlashskyaiAgentCatalog {
  FlashskyaiAgentCatalog._();

  /// Dropdown sentinel: clear `--agent`.
  static const noneDropdownValue = '__fsk_agent_none__';

  /// Dropdown sentinel: free-text `--agent` id.
  static const customDropdownValue = '__fsk_agent_custom__';

  static const List<FlashskyaiBuiltinAgentEntry> builtIns = [
    FlashskyaiBuiltinAgentEntry(
      id: 'flashskyai-code-guide',
      modelHintEn: 'haiku',
      modelHintZh: 'haiku',
    ),
    FlashskyaiBuiltinAgentEntry(
      id: 'general-purpose',
      modelHintEn: 'inherit',
      modelHintZh: 'inherit',
    ),
    FlashskyaiBuiltinAgentEntry(
      id: 'statusline-setup',
      modelHintEn: 'sonnet',
      modelHintZh: 'sonnet',
    ),
  ];

  static FlashskyaiBuiltinAgentEntry? tryParseBuiltinId(String id) {
    for (final e in builtIns) {
      if (e.id == id) return e;
    }
    return null;
  }

  static bool isKnownAgentId(
    String id, {
    List<String> userAgentIds = const [],
  }) {
    if (tryParseBuiltinId(id) != null) return true;
    return userAgentIds.contains(id);
  }

  static List<String> dropdownValues({List<String> userAgentIds = const []}) =>
      [
        noneDropdownValue,
        ...builtIns.map((e) => e.id),
        ...userAgentIds,
        customDropdownValue,
      ];

  static String activeDropdownValue(
    String agent, {
    List<String> userAgentIds = const [],
  }) {
    final t = agent.trim();
    if (t.isEmpty) return noneDropdownValue;
    if (tryParseBuiltinId(t) != null) return t;
    if (userAgentIds.contains(t)) return t;
    return customDropdownValue;
  }
}

/// Lists user-defined agent ids from `config-profiles/flashskyai/agents/*.md`.
class FlashskyaiAgentCatalogService {
  FlashskyaiAgentCatalogService({FlashskyaiStorageRoots? storageRoots})
    : _storageRoots = storageRoots;

  final FlashskyaiStorageRoots? _storageRoots;

  /// Agent id from `image-analyzer.md` → `image-analyzer`.
  static String? agentIdFromMdFilename(String filename) {
    if (!filename.endsWith('.md')) return null;
    final id = filename.substring(0, filename.length - 3).trim();
    if (id.isEmpty || id.startsWith('.')) return null;
    return id;
  }

  Future<List<String>> listUserAgentIds() async {
    if (_storageRoots != null) {
      final snap = await _storageRoots.resolve();
      final agentsDir = snap.fs.pathContext.join(
        snap.layout.appToolRoot('flashskyai'),
        'agents',
      );
      return _listWithFs(snap.fs, agentsDir);
    }
    final fs = AppStorage.fs;
    final layout = CliDataLayout(
      teampilotRoot: AppStorage.paths.basePath,
      fs: fs,
    );
    return _listWithFs(
      fs,
      fs.pathContext.join(layout.appToolRoot('flashskyai'), 'agents'),
    );
  }

  Future<List<String>> _listWithFs(Filesystem fs, String agentsDir) async {
    try {
      if (!(await fs.stat(agentsDir)).isDirectory) return const [];
      final ids = <String>[];
      for (final entry in await fs.listDir(agentsDir)) {
        if (entry.isDirectory) continue;
        final id = agentIdFromMdFilename(entry.name);
        if (id != null) ids.add(id);
      }
      ids.sort();
      return ids;
    } on Object {
      return const [];
    }
  }
}
