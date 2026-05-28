import 'package:flutter/foundation.dart';

enum McpRegistrySourceKind {
  smithery,
  officialRegistry;

  String get wireValue => switch (this) {
    McpRegistrySourceKind.smithery => 'smithery',
    McpRegistrySourceKind.officialRegistry => 'official_registry',
  };

  static McpRegistrySourceKind decode(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v == 'official_registry' || v == 'official') {
      return McpRegistrySourceKind.officialRegistry;
    }
    return McpRegistrySourceKind.smithery;
  }
}

@immutable
class McpRegistrySourceConfig {
  const McpRegistrySourceConfig({
    required this.kind,
    required this.baseUrl,
    this.enabled = true,
    this.apiToken,
  });

  final McpRegistrySourceKind kind;
  final String baseUrl;
  final bool enabled;

  /// Smithery: `Authorization: Bearer …` (optional).
  final String? apiToken;

  bool get hasApiToken => apiToken != null && apiToken!.trim().isNotEmpty;

  static String defaultBaseUrl(McpRegistrySourceKind kind) => switch (kind) {
    McpRegistrySourceKind.smithery => 'https://api.smithery.ai',
    McpRegistrySourceKind.officialRegistry =>
      'https://registry.modelcontextprotocol.io/v0/servers',
  };

  McpRegistrySourceConfig copyWith({
    String? baseUrl,
    bool? enabled,
    String? apiToken,
    bool clearApiToken = false,
  }) => McpRegistrySourceConfig(
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    enabled: enabled ?? this.enabled,
    apiToken: clearApiToken ? null : (apiToken ?? this.apiToken),
  );

  Map<String, Object?> toJson() => {
    'kind': kind.wireValue,
    'baseUrl': baseUrl,
    'enabled': enabled,
    if (hasApiToken) 'apiToken': apiToken!.trim(),
  };

  factory McpRegistrySourceConfig.fromJson(Map<String, Object?> json) {
    final kind = McpRegistrySourceKind.decode(json['kind'] as String?);
    return McpRegistrySourceConfig(
      kind: kind,
      baseUrl:
          (json['baseUrl'] as String?)?.trim().isNotEmpty == true
              ? json['baseUrl'] as String
              : defaultBaseUrl(kind),
      enabled: json['enabled'] as bool? ?? true,
      apiToken: json['apiToken'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpRegistrySourceConfig &&
          kind == other.kind &&
          baseUrl == other.baseUrl &&
          enabled == other.enabled &&
          apiToken == other.apiToken;

  @override
  int get hashCode => Object.hash(kind, baseUrl, enabled, apiToken);
}

@immutable
class McpRegistrySourcesConfig {
  const McpRegistrySourcesConfig({required this.sources});

  final List<McpRegistrySourceConfig> sources;

  static McpRegistrySourcesConfig defaults() => McpRegistrySourcesConfig(
    sources: [
      McpRegistrySourceConfig(
        kind: McpRegistrySourceKind.smithery,
        baseUrl: McpRegistrySourceConfig.defaultBaseUrl(
          McpRegistrySourceKind.smithery,
        ),
      ),
      McpRegistrySourceConfig(
        kind: McpRegistrySourceKind.officialRegistry,
        baseUrl: McpRegistrySourceConfig.defaultBaseUrl(
          McpRegistrySourceKind.officialRegistry,
        ),
      ),
    ],
  );

  McpRegistrySourceConfig? byKind(McpRegistrySourceKind kind) {
    for (final s in sources) {
      if (s.kind == kind) return s;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'sources': sources.map((s) => s.toJson()).toList(),
  };

  factory McpRegistrySourcesConfig.fromJson(Map<String, Object?> json) {
    final raw = json['sources'];
    if (raw is! List || raw.isEmpty) return defaults();
    final parsed = raw
        .whereType<Map>()
        .map((m) => McpRegistrySourceConfig.fromJson(m.cast<String, Object?>()))
        .toList();
    if (parsed.isEmpty) return defaults();
    final byKind = {for (final s in parsed) s.kind: s};
    return McpRegistrySourcesConfig(
      sources: [
        byKind[McpRegistrySourceKind.smithery] ??
            McpRegistrySourcesConfig.defaults().byKind(
              McpRegistrySourceKind.smithery,
            )!,
        byKind[McpRegistrySourceKind.officialRegistry] ??
            McpRegistrySourcesConfig.defaults().byKind(
              McpRegistrySourceKind.officialRegistry,
            )!,
      ],
    );
  }
}
