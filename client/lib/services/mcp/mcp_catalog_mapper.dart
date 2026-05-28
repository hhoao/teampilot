import 'dart:io';

import '../../config/mcp_presets.dart';
import '../../models/mcp_catalog_listing.dart';
import '../../models/mcp_server.dart';

/// Maps remote catalog rows into [McpCatalogListing] / draft [McpServer].
class McpCatalogMapper {
  static String sanitizeId(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  static String _mapRemoteType(String type) {
    final t = type.trim().toLowerCase();
    return switch (t) {
      'streamable-http' || 'http' => 'http',
      'sse' => 'sse',
      _ => 'http',
    };
  }

  static Map<String, Object?>? _npxStdio(String package) {
    if (Platform.isWindows) {
      return {
        'type': 'stdio',
        'command': 'cmd',
        'args': ['/c', 'npx', '-y', package],
      };
    }
    return {
      'type': 'stdio',
      'command': 'npx',
      'args': ['-y', package],
    };
  }

  static Map<String, Object?>? _uvxStdio(String package) {
    return {
      'type': 'stdio',
      'command': 'uvx',
      'args': [package],
    };
  }

  static Map<String, Object?>? serverSpecFromRegistryServer(
    Map<String, Object?> server,
  ) {
    final remotes = server['remotes'];
    if (remotes is List && remotes.isNotEmpty) {
      final remote = (remotes.first as Map).cast<String, Object?>();
      final url = remote['url']?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        return {
          'type': _mapRemoteType(remote['type']?.toString() ?? 'http'),
          'url': url,
        };
      }
    }

    final packages = server['packages'];
    if (packages is List && packages.isNotEmpty) {
      final pkg = (packages.first as Map).cast<String, Object?>();
      final transport = pkg['transport'];
      if (transport is Map &&
          transport['type']?.toString().toLowerCase() == 'stdio') {
        final identifier = pkg['identifier']?.toString().trim() ?? '';
        if (identifier.isEmpty) return null;
        return switch (pkg['registryType']?.toString().toLowerCase()) {
          'npm' => _npxStdio(identifier),
          'pypi' => _uvxStdio(identifier),
          _ => null,
        };
      }
    }
    return null;
  }

  /// Smithery remote MCP gateway (list API omits [deploymentUrl]).
  static String smitheryGatewayUrl(String qualifiedName) {
    final name = qualifiedName.trim();
    if (name.isEmpty) return '';
    final path = name.startsWith('@') ? name : '@$name';
    return 'https://server.smithery.ai/$path';
  }

  static Map<String, Object?>? serverSpecFromSmitheryJson(
    Map<String, Object?> json,
  ) {
    final qualifiedName = json['qualifiedName']?.toString().trim() ?? '';

    final deploymentUrl = json['deploymentUrl']?.toString().trim();
    if (deploymentUrl != null && deploymentUrl.isNotEmpty) {
      return {'type': 'http', 'url': deploymentUrl};
    }

    final connections = json['connections'];
    if (connections is List && connections.isNotEmpty) {
      final conn = (connections.first as Map).cast<String, Object?>();
      final url = conn['deploymentUrl']?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        return {'type': 'http', 'url': url};
      }
    }

    if (qualifiedName.isNotEmpty) {
      return {'type': 'http', 'url': smitheryGatewayUrl(qualifiedName)};
    }
    return null;
  }

  static McpCatalogListing? fromSmitheryJson(Map<String, Object?> json) {
    final qualifiedName = json['qualifiedName']?.toString().trim() ?? '';
    if (qualifiedName.isEmpty) return null;

    final spec = serverSpecFromSmitheryJson(json);
    if (spec == null) return null;

    final displayName = json['displayName']?.toString().trim();
    final tags = <String>[
      'smithery',
      if (json['remote'] == true) 'remote',
      if (json['verified'] == true) 'verified',
    ];

    return McpCatalogListing(
      id: sanitizeId(qualifiedName),
      title: displayName?.isNotEmpty == true ? displayName! : qualifiedName,
      description: json['description']?.toString().trim() ?? '',
      source: McpCatalogSource.smithery,
      serverSpec: spec,
      iconUrl: json['iconUrl']?.toString(),
      homepage: json['homepage']?.toString(),
      tags: tags,
      useCount: (json['useCount'] as num?)?.toInt(),
      verified: json['verified'] == true,
      remote: json['remote'] == true,
      smitheryQualifiedName: qualifiedName,
    );
  }

  /// Prefer detail API [deploymentUrl] over list gateway fallback.
  static McpCatalogListing applySmitheryDetail(
    McpCatalogListing listing,
    Map<String, Object?> detail,
  ) {
    final spec = serverSpecFromSmitheryJson(detail) ?? listing.serverSpec;
    return McpCatalogListing(
      id: listing.id,
      title: listing.title,
      description: listing.description.isNotEmpty
          ? listing.description
          : (detail['description']?.toString().trim() ?? ''),
      source: listing.source,
      serverSpec: spec,
      iconUrl: listing.iconUrl ?? detail['iconUrl']?.toString(),
      homepage: listing.homepage ?? detail['homepage']?.toString(),
      docs: listing.docs,
      tags: listing.tags,
      useCount: listing.useCount ?? (detail['useCount'] as num?)?.toInt(),
      verified: listing.verified || detail['verified'] == true,
      remote: listing.remote || detail['remote'] == true,
      smitheryQualifiedName: listing.smitheryQualifiedName,
    );
  }

  static McpCatalogListing? fromRegistryEntry(Map<String, Object?> entry) {
    final serverRaw = entry['server'];
    if (serverRaw is! Map) return null;
    final server = serverRaw.cast<String, Object?>();

    final meta = entry['_meta'];
    if (meta is Map) {
      final official =
          meta['io.modelcontextprotocol.registry/official'] as Map?;
      if (official != null) {
        if (official['isLatest'] != true) return null;
        final status = official['status']?.toString();
        if (status != null && status != 'active') return null;
      }
    }

    final spec = serverSpecFromRegistryServer(server);
    if (spec == null) return null;

    final name = server['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final title =
        server['title']?.toString().trim().isNotEmpty == true
            ? server['title']!.toString().trim()
            : name.split('/').last;

    final repo = server['repository'];
    String? repoUrl;
    if (repo is Map) {
      repoUrl = repo['url']?.toString();
    }

    return McpCatalogListing(
      id: sanitizeId(name),
      title: title,
      description: server['description']?.toString().trim() ?? '',
      source: McpCatalogSource.officialRegistry,
      serverSpec: spec,
      homepage: server['websiteUrl']?.toString() ?? repoUrl,
      docs: repoUrl,
      tags: const ['registry'],
    );
  }

  static McpCatalogListing fromPreset(McpPreset preset) {
    return McpCatalogListing(
      id: preset.id,
      title: preset.name,
      description: preset.description,
      source: McpCatalogSource.builtin,
      serverSpec: preset.server,
      homepage: preset.homepage.isNotEmpty ? preset.homepage : null,
      docs: preset.docs.isNotEmpty ? preset.docs : null,
      tags: preset.tags,
    );
  }

  static McpServer draftFromListing(
    McpCatalogListing listing, {
    required int now,
    String? existingId,
  }) {
    return McpServer(
      id: existingId ?? listing.id,
      name: listing.title,
      server: Map<String, Object?>.from(listing.serverSpec),
      description: listing.description,
      tags: listing.tags,
      homepage: listing.homepage ?? '',
      docs: listing.docs ?? '',
      enabled: true,
      createdAt: now,
      updatedAt: now,
      source: McpServerSource.catalog,
    );
  }
}
