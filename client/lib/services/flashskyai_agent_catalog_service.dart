import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'app_storage.dart';
import 'cli_data_layout.dart';
import 'flashskyai_storage_roots.dart';
import 'remote_file_store.dart';

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
      final agentsDir = p.Context(
        style: snap.storageIsRemote ? p.Style.posix : p.Style.platform,
      ).join(snap.layout.appToolRoot('flashskyai'), 'agents');
      if (snap.storageIsRemote && snap.remoteFileStore != null) {
        return _listRemote(snap.remoteFileStore!, agentsDir);
      }
      return _listLocal(agentsDir);
    }
    final layout = CliDataLayout(teampilotRoot: AppStorage.basePath);
    return _listLocal(p.join(layout.appToolRoot('flashskyai'), 'agents'));
  }

  Future<List<String>> _listLocal(String agentsDir) async {
    final dir = Directory(agentsDir);
    if (!await dir.exists()) return const [];
    final ids = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final id = agentIdFromMdFilename(p.basename(entity.path));
      if (id != null) ids.add(id);
    }
    ids.sort();
    return ids;
  }

  Future<List<String>> _listRemote(
    RemoteFileStore store,
    String agentsDir,
  ) async {
    try {
      if (!await store.fileExists(agentsDir)) return const [];
      final entries = await store.listDirectoryEntries(agentsDir);
      final ids = <String>[];
      for (final entry in entries) {
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
