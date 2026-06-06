import 'dart:convert';

import '../../team_bus/mcp/teammate_bus_mcp_config.dart';

/// Mixed-mode defaults merged into `$HOME/.cursor/cli-config.json`.
///
/// Cursor CLI matches MCP allow entries as `Mcp(server:tool)` inside
/// `permissions.allow` (see cursor-agent `matchesMcpEntry`).
abstract final class CursorCliConfigPolicy {
  CursorCliConfigPolicy._();

  /// All tools on the TeamPilot teammate-bus MCP server (list_teammates,
  /// wait_for_message, send_message, …).
  static String get teamBusMcpAllowEntry =>
      'Mcp($teammateBusMcpServerName:*)';

  static const defaultVersion = 1;

  /// Merges teammate-bus auto-approve into [config] without clobbering auth or
  /// other provider-owned fields.
  static Map<String, Object?> applyMixedTeamSessionPolicy(
    Map<String, Object?> config,
  ) {
    final merged = Map<String, Object?>.from(config);
    final permissions = Map<String, Object?>.from(
      (merged['permissions'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existingAllow = <String>[
      for (final entry in (permissions['allow'] as List?) ?? const [])
        if (entry is String) entry,
    ];
    permissions['allow'] = <String>{
      ...existingAllow,
      teamBusMcpAllowEntry,
    }.toList(growable: false);
    merged['permissions'] = permissions;
    merged.putIfAbsent('version', () => defaultVersion);
    return merged;
  }

  static Map<String, Object?>? parseConfigJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return decoded.cast<String, Object?>();
    } on Object {
      return null;
    }
  }
}
