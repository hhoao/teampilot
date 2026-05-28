import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/mcp_catalog_listing.dart';
import 'mcp_catalog_mapper.dart';

class McpRegistryBrowseResult {
  const McpRegistryBrowseResult({
    required this.items,
    required this.nextCursor,
    required this.query,
  });

  final List<McpCatalogListing> items;
  final String? nextCursor;
  final String query;
}

/// Official MCP Registry API — https://registry.modelcontextprotocol.io
class McpRegistryBrowseService {
  McpRegistryBrowseService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<McpRegistryBrowseResult> search(
    String query, {
    required String baseUrl,
    String? cursor,
    int pageSize = 20,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final params = <String, String>{
      'pageSize': '$pageSize',
      if (query.trim().isNotEmpty) 'search': query.trim(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.parse(root).replace(queryParameters: params);
    final resp = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw McpRegistryBrowseException('Registry HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final servers = body['servers'] as List<dynamic>? ?? [];
    final items = <McpCatalogListing>[];
    for (final raw in servers) {
      if (raw is! Map) continue;
      final listing = McpCatalogMapper.fromRegistryEntry(
        raw.cast<String, Object?>(),
      );
      if (listing != null) items.add(listing);
    }
    final metadata = body['metadata'] as Map<String, dynamic>?;
    return McpRegistryBrowseResult(
      items: items,
      nextCursor: metadata?['nextCursor'] as String?,
      query: query,
    );
  }

  void close() => _client.close();
}

class McpRegistryBrowseException implements Exception {
  McpRegistryBrowseException(this.message);
  final String message;
  @override
  String toString() => message;
}
