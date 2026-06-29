import 'package:flutter/foundation.dart';

enum McpCatalogSource {
  builtin,
  smithery,
  officialRegistry;

  String get wireValue => switch (this) {
    McpCatalogSource.builtin => 'builtin',
    McpCatalogSource.smithery => 'smithery',
    McpCatalogSource.officialRegistry => 'official_registry',
  };
}

/// One browsable MCP entry from Smithery or the official registry API.
@immutable
class McpCatalogListing {
  const McpCatalogListing({
    required this.id,
    required this.title,
    required this.description,
    required this.source,
    required this.serverSpec,
    this.iconUrl,
    this.homepage,
    this.docs,
    this.tags = const [],
    this.useCount,
    this.verified = false,
    this.remote = false,
    this.smitheryQualifiedName,
  });

  final String id;
  final String title;
  final String description;
  final McpCatalogSource source;
  final Map<String, Object?> serverSpec;
  final String? iconUrl;
  final String? homepage;
  final String? docs;
  final List<String> tags;
  final int? useCount;
  final bool verified;
  final bool remote;

  /// Set for Smithery list rows; detail API has the real [deploymentUrl].
  final String? smitheryQualifiedName;

  bool get canInstall => serverSpec.isNotEmpty;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'source': source.wireValue,
    'serverSpec': serverSpec,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (homepage != null) 'homepage': homepage,
    if (docs != null) 'docs': docs,
    if (tags.isNotEmpty) 'tags': tags,
    if (useCount != null) 'useCount': useCount,
    if (verified) 'verified': verified,
    if (remote) 'remote': remote,
    if (smitheryQualifiedName != null)
      'smitheryQualifiedName': smitheryQualifiedName,
  };

  factory McpCatalogListing.fromJson(Map<String, Object?> json) {
    final tagsRaw = json['tags'];
    return McpCatalogListing(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      source: McpCatalogSourceWire.fromWireValue(
        json['source'] as String? ?? '',
      ),
      serverSpec: (json['serverSpec'] as Map?)?.cast<String, Object?>() ?? const {},
      iconUrl: json['iconUrl'] as String?,
      homepage: json['homepage'] as String?,
      docs: json['docs'] as String?,
      tags: tagsRaw is List
          ? tagsRaw.map((e) => e.toString()).toList()
          : const [],
      useCount: (json['useCount'] as num?)?.toInt(),
      verified: json['verified'] == true,
      remote: json['remote'] == true,
      smitheryQualifiedName: json['smitheryQualifiedName'] as String?,
    );
  }
}

extension McpCatalogSourceWire on McpCatalogSource {
  static McpCatalogSource fromWireValue(String raw) => switch (raw) {
    'builtin' => McpCatalogSource.builtin,
    'smithery' => McpCatalogSource.smithery,
    'official_registry' => McpCatalogSource.officialRegistry,
    _ => McpCatalogSource.builtin,
  };
}
