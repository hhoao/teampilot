import 'dart:convert';

import '../../models/mcp_catalog_listing.dart';
import '../../utils/logger.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Remote MCP discovery sources persisted under [mcpDiscoveryCacheSmithery] /
/// [mcpDiscoveryCacheOfficial].
const mcpDiscoveryCacheSmithery = 'smithery';
const mcpDiscoveryCacheOfficial = 'official';

/// On-disk snapshot for one remote MCP discovery source (empty-query browse).
class McpDiscoveryDiskSnapshot {
  const McpDiscoveryDiskSnapshot({
    required this.items,
    required this.query,
    required this.syncedAtMs,
    this.smitheryPage = 1,
    this.smitheryTotalPages = 1,
    this.registryCursor,
    this.registryNextCursor,
  });

  final List<McpCatalogListing> items;
  final String query;
  final int syncedAtMs;
  final int smitheryPage;
  final int smitheryTotalPages;
  final String? registryCursor;
  final String? registryNextCursor;
}

/// Disk-backed MCP discovery cache (Smithery + official registry browse lists).
///
/// Layout under [AppStorage.paths.mcpDiscoveryCacheDir]:
/// `{smithery|official}/meta.json`, `listings.json`.
///
/// Only empty-query browse results are persisted (search hits stay in memory).
class McpDiscoveryDiskCacheService {
  McpDiscoveryDiskCacheService({Filesystem? filesystem})
    : _fsOverride = filesystem;

  final Filesystem? _fsOverride;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _cacheRoot => AppStorage.paths.mcpDiscoveryCacheDir;

  String _sourceDir(String sourceKey) =>
      _fs.pathContext.join(_cacheRoot, sourceKey);

  Future<McpDiscoveryDiskSnapshot?> read(String sourceKey) async {
    final dir = _sourceDir(sourceKey);
    final listingsPath = _fs.pathContext.join(dir, 'listings.json');
    final metaPath = _fs.pathContext.join(dir, 'meta.json');
    final listingsStat = await _fs.stat(listingsPath);
    if (!listingsStat.isFile) return null;
    try {
      final listingsText = await _fs.readString(listingsPath);
      if (listingsText == null) return null;
      final listingsJson = json.decode(listingsText) as List<dynamic>;
      final items = listingsJson
          .map(
            (e) => McpCatalogListing.fromJson(
              (e as Map).cast<String, Object?>(),
            ),
          )
          .toList();

      var query = '';
      var syncedAtMs = 0;
      var smitheryPage = 1;
      var smitheryTotalPages = 1;
      String? registryCursor;
      String? registryNextCursor;

      final metaStat = await _fs.stat(metaPath);
      if (metaStat.isFile) {
        final metaText = await _fs.readString(metaPath);
        if (metaText != null) {
          final meta = (json.decode(metaText) as Map).cast<String, Object?>();
          query = meta['query'] as String? ?? '';
          syncedAtMs = meta['syncedAtMs'] as int? ?? 0;
          smitheryPage = meta['smitheryPage'] as int? ?? 1;
          smitheryTotalPages = meta['smitheryTotalPages'] as int? ?? 1;
          registryCursor = meta['registryCursor'] as String?;
          registryNextCursor = meta['registryNextCursor'] as String?;
        }
      }

      return McpDiscoveryDiskSnapshot(
        items: items,
        query: query,
        syncedAtMs: syncedAtMs,
        smitheryPage: smitheryPage,
        smitheryTotalPages: smitheryTotalPages,
        registryCursor: registryCursor,
        registryNextCursor: registryNextCursor,
      );
    } catch (e) {
      appLogger.w('[McpDiscoveryCache] corrupt cache for $sourceKey: $e');
      return null;
    }
  }

  Future<void> write({
    required String sourceKey,
    required McpDiscoveryDiskSnapshot snapshot,
  }) async {
    if (snapshot.query.isNotEmpty) return;

    final dir = _sourceDir(sourceKey);
    final tmpDir = '$dir.tmp';
    await _fs.removeRecursive(tmpDir);
    await _fs.ensureDir(tmpDir);

    final listingsJson = const JsonEncoder.withIndent(
      '  ',
    ).convert(snapshot.items.map((e) => e.toJson()).toList());
    await _fs.writeString(
      _fs.pathContext.join(tmpDir, 'listings.json'),
      listingsJson,
    );

    final meta = <String, Object?>{
      'query': snapshot.query,
      'syncedAtMs': snapshot.syncedAtMs,
      'smitheryPage': snapshot.smitheryPage,
      'smitheryTotalPages': snapshot.smitheryTotalPages,
      if (snapshot.registryCursor != null)
        'registryCursor': snapshot.registryCursor,
      if (snapshot.registryNextCursor != null)
        'registryNextCursor': snapshot.registryNextCursor,
    };
    await _fs.writeString(
      _fs.pathContext.join(tmpDir, 'meta.json'),
      const JsonEncoder.withIndent('  ').convert(meta),
    );

    await _fs.ensureDir(_cacheRoot);
    final backupDir = '$dir.bak';
    await _fs.removeRecursive(backupDir);
    try {
      final dirStat = await _fs.stat(dir);
      if (dirStat.exists) {
        await _fs.rename(dir, backupDir);
      }
      await _fs.rename(tmpDir, dir);
      await _fs.removeRecursive(backupDir);
    } catch (e) {
      final backupStat = await _fs.stat(backupDir);
      if (backupStat.exists) {
        await _fs.removeRecursive(dir);
        await _fs.rename(backupDir, dir);
      }
      rethrow;
    } finally {
      await _fs.removeRecursive(tmpDir);
    }
  }

  Future<void> delete(String sourceKey) async {
    final dir = _sourceDir(sourceKey);
    final dirStat = await _fs.stat(dir);
    if (dirStat.exists) {
      await _fs.removeRecursive(dir);
    }
    await _fs.removeRecursive('$dir.tmp');
  }
}
