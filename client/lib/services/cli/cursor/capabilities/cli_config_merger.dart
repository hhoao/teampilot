import '../provider/cursor_cli_config_policy.dart';
import '../../../team_bus/mcp/teammate_bus_mcp_config.dart';

/// Pure helpers for session warm-tier `cli-config.base.json` and per-member merge.
abstract final class CursorCliConfigMerger {
  CursorCliConfigMerger._();

  /// Session-shared slice of the user's global `cli-config.json`.
  ///
  /// Keeps network/server caches and non-bus permission allows; bus MCP entries
  /// are member overlay concerns applied via [mergeMemberConfig].
  static Map<String, Object?> extractWarmTier(Map<String, Object?> userConfig) {
    final warm = <String, Object?>{};

    final serverConfigCache = userConfig['serverConfigCache'];
    if (serverConfigCache != null) {
      warm['serverConfigCache'] = serverConfigCache;
    }

    final network = userConfig['network'];
    if (network != null) {
      warm['network'] = network;
    }

    final userPermissions =
        (userConfig['permissions'] as Map?)?.cast<String, Object?>();
    if (userPermissions != null) {
      final permissions = <String, Object?>{};

      final allow = <String>[
        for (final entry in (userPermissions['allow'] as List?) ?? const [])
          if (entry is String && !_isTeammateBusAllowEntry(entry)) entry,
      ];
      if (allow.isNotEmpty) {
        permissions['allow'] = allow;
      }

      final deny = userPermissions['deny'];
      if (deny != null) {
        permissions['deny'] = deny;
      }

      if (permissions.isNotEmpty) {
        warm['permissions'] = permissions;
      }
    }

    return warm;
  }

  /// Merges session [base] with per-member [memberOverrides], then applies mixed
  /// team MCP auto-approve policy.
  static Map<String, Object?> mergeMemberConfig({
    required Map<String, Object?> base,
    required Map<String, Object?> memberOverrides,
  }) {
    final merged = Map<String, Object?>.from(base);

    for (final entry in memberOverrides.entries) {
      if (entry.key == 'permissions' && entry.value is Map) {
        merged['permissions'] = _mergePermissions(
          (merged['permissions'] as Map?)?.cast<String, Object?>() ??
              const {},
          (entry.value as Map).cast<String, Object?>(),
        );
      } else {
        merged[entry.key] = entry.value;
      }
    }

    return CursorCliConfigPolicy.applyMixedTeamSessionPolicy(merged);
  }

  static Map<String, Object?> _mergePermissions(
    Map<String, Object?> base,
    Map<String, Object?> overrides,
  ) {
    final merged = Map<String, Object?>.from(base);
    for (final entry in overrides.entries) {
      if (entry.key == 'allow' || entry.key == 'deny') {
        final combined = <String>{
          for (final value in (merged[entry.key] as List?) ?? const [])
            if (value is String) value,
          for (final value in (entry.value as List?) ?? const [])
            if (value is String) value,
        };
        merged[entry.key] = combined.toList(growable: false);
      } else {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  static bool _isTeammateBusAllowEntry(String entry) {
    if (entry == CursorCliConfigPolicy.teamBusMcpAllowEntry) return true;
    return entry.startsWith('Mcp($teammateBusMcpServerName:');
  }
}
