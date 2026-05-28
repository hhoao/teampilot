import 'package:flutter/foundation.dart';

enum McpServerSource {
  catalog,
  imported;

  static McpServerSource decode(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    if (value == 'imported') return McpServerSource.imported;
    return McpServerSource.catalog;
  }

  String get wireValue => switch (this) {
    McpServerSource.catalog => 'catalog',
    McpServerSource.imported => 'imported',
  };
}

/// Parses comma-separated tags (cc-switch style).
List<String> parseMcpTags(String raw) {
  return raw
      .split(',')
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toList();
}

@immutable
class McpServer {
  const McpServer({
    required this.id,
    required this.name,
    required this.server,
    this.enabled = true,
    this.description = '',
    this.tags = const [],
    this.homepage = '',
    this.docs = '',
    this.source = McpServerSource.catalog,
    this.smitheryHosted = false,
    this.importedFrom,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  final String id;
  final String name;
  final Map<String, Object?> server;
  final bool enabled;
  final String description;
  final List<String> tags;
  final String homepage;
  final String docs;
  final McpServerSource source;

  /// Installed from Smithery; session merge may attach registry Bearer token.
  final bool smitheryHosted;

  final String? importedFrom;
  final int createdAt;
  final int updatedAt;

  /// Key used in CLI `mcpServers` maps (user scope).
  String get configKey {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed : id;
  }

  bool get hasMetadata =>
      description.trim().isNotEmpty ||
      tags.isNotEmpty ||
      homepage.trim().isNotEmpty ||
      docs.trim().isNotEmpty;

  McpServer copyWith({
    String? id,
    String? name,
    Map<String, Object?>? server,
    bool? enabled,
    String? description,
    List<String>? tags,
    String? homepage,
    String? docs,
    McpServerSource? source,
    bool? smitheryHosted,
    String? importedFrom,
    int? createdAt,
    int? updatedAt,
    bool clearImportedFrom = false,
  }) {
    return McpServer(
      id: id ?? this.id,
      name: name ?? this.name,
      server: server ?? this.server,
      enabled: enabled ?? this.enabled,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      homepage: homepage ?? this.homepage,
      docs: docs ?? this.docs,
      source: source ?? this.source,
      smitheryHosted: smitheryHosted ?? this.smitheryHosted,
      importedFrom: clearImportedFrom
          ? null
          : (importedFrom ?? this.importedFrom),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'server': server,
    'enabled': enabled,
    if (description.isNotEmpty) 'description': description,
    if (tags.isNotEmpty) 'tags': tags,
    if (homepage.isNotEmpty) 'homepage': homepage,
    if (docs.isNotEmpty) 'docs': docs,
    'source': source.wireValue,
    if (smitheryHosted) 'smitheryHosted': true,
    if (importedFrom != null && importedFrom!.isNotEmpty)
      'importedFrom': importedFrom,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory McpServer.fromJson(Map<String, Object?> json) {
    final serverRaw = json['server'];
    final tagsRaw = json['tags'];
    final tags = tagsRaw is List
        ? tagsRaw.map((e) => e.toString()).where((t) => t.isNotEmpty).toList()
        : const <String>[];
    return McpServer(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      server: serverRaw is Map
          ? serverRaw.cast<String, Object?>()
          : const <String, Object?>{},
      enabled: json['enabled'] as bool? ?? true,
      description: json['description'] as String? ?? '',
      tags: tags,
      homepage: json['homepage'] as String? ?? '',
      docs: json['docs'] as String? ?? '',
      source: McpServerSource.decode(json['source']),
      smitheryHosted:
          json['smitheryHosted'] as bool? ?? tags.contains('smithery'),
      importedFrom: json['importedFrom'] as String?,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is McpServer &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          mapEquals(server, other.server) &&
          enabled == other.enabled &&
          description == other.description &&
          listEquals(tags, other.tags) &&
          homepage == other.homepage &&
          docs == other.docs &&
          source == other.source &&
          smitheryHosted == other.smitheryHosted &&
          importedFrom == other.importedFrom &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    Object.hashAll(server.entries),
    enabled,
    description,
    Object.hashAll(tags),
    homepage,
    docs,
    source,
    smitheryHosted,
    importedFrom,
    createdAt,
    updatedAt,
  );
}
