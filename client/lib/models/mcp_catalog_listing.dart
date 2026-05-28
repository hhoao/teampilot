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
}
