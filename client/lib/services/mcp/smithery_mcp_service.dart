import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/mcp_catalog_listing.dart';
import 'mcp_catalog_mapper.dart';

class SmitherySearchResult {
  const SmitherySearchResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.query,
  });

  final List<McpCatalogListing> items;
  final int page;
  final int totalPages;
  final String query;
}

class SmitheryMcpService {
  SmitheryMcpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Map<String, String> _authHeaders(String? apiToken) {
    final token = apiToken?.trim() ?? '';
    if (token.isEmpty) return const {};
    return {'Authorization': 'Bearer $token'};
  }

  /// GET /servers/{qualifiedName} — includes [deploymentUrl] missing from list.
  Future<Map<String, Object?>?> fetchServerDetail(
    String qualifiedName, {
    required String baseUrl,
    String? apiToken,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final encoded = Uri.encodeComponent(qualifiedName);
    final uri = Uri.parse('$root/servers/$encoded');
    final resp = await _client
        .get(uri, headers: _authHeaders(apiToken))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw SmitheryMcpException('Smithery HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body);
    if (body is! Map) return null;
    return body.cast<String, Object?>();
  }

  Future<SmitherySearchResult> search(
    String query, {
    required String baseUrl,
    String? apiToken,
    int page = 1,
    int pageSize = 20,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$root/servers').replace(
      queryParameters: {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        'page': '$page',
        'pageSize': '$pageSize',
      },
    );
    final resp = await _client
        .get(uri, headers: _authHeaders(apiToken))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw SmitheryMcpException('Smithery HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final servers = body['servers'] as List<dynamic>? ?? [];
    final items = <McpCatalogListing>[];
    for (final raw in servers) {
      if (raw is! Map) continue;
      final listing = McpCatalogMapper.fromSmitheryJson(
        raw.cast<String, Object?>(),
      );
      if (listing != null) items.add(listing);
    }
    final pagination = body['pagination'] as Map<String, dynamic>?;
    return SmitherySearchResult(
      items: items,
      page: (pagination?['currentPage'] as num?)?.toInt() ?? page,
      totalPages: (pagination?['totalPages'] as num?)?.toInt() ?? 1,
      query: query,
    );
  }

  void close() => _client.close();
}

class SmitheryMcpException implements Exception {
  SmitheryMcpException(this.message);
  final String message;
  @override
  String toString() => message;
}
