import '../models/mcp_server.dart';
import '../services/mcp/mcp_catalog_service.dart';
import '../services/mcp/mcp_server_validator.dart';
import '../services/storage/app_storage.dart';

class McpRepository {
  McpRepository({
    McpCatalogService? catalog,
    McpServerValidator? validator,
  }) : _catalog = catalog,
       _validator = validator ?? McpServerValidator();

  final McpCatalogService? _catalog;
  final McpServerValidator _validator;

  List<McpServer>? _cache;

  void invalidateCache() => _cache = null;

  Future<McpCatalogService> _resolveCatalog() async {
    final injected = _catalog;
    if (injected != null) return injected;
    if (AppStorage.isInstalled) {
      final roots = AppStorage.context;
      return McpCatalogService(
        catalogPath: roots.mcpServersJsonPath,
        fs: roots.fs,
      );
    }
    return McpCatalogService(catalogPath: AppStorage.paths.mcpServersJson);
  }

  Future<List<McpServer>> loadAll({bool forceReload = false}) async {
    if (!forceReload && _cache != null) return _cache!;
    final catalog = await _resolveCatalog();
    _cache = await catalog.loadAll();
    return _cache!;
  }

  Future<McpServer?> findById(String id) async {
    final list = await loadAll();
    try {
      return list.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  List<String> validate(McpServer server) => _validator.validate(
    McpServerFields(
      id: server.id,
      name: server.name,
      server: server.server,
      homepage: server.homepage,
      docs: server.docs,
    ),
  );

  Future<McpServer> upsert(McpServer server) async {
    final errors = validate(server);
    if (errors.isNotEmpty) {
      throw McpValidationException(errors);
    }
    final catalog = await _resolveCatalog();
    await catalog.upsert(server);
    if (_cache != null) {
      _cache = [..._cache!.where((s) => s.id != server.id), server];
    } else {
      _cache = await catalog.loadAll();
    }
    return server;
  }

  Future<void> deleteById(String id) async {
    final catalog = await _resolveCatalog();
    await catalog.deleteById(id);
    if (_cache != null) {
      _cache = _cache!.where((s) => s.id != id).toList();
    }
  }

  Future<McpCatalogService> catalogService() => _resolveCatalog();
}

class McpValidationException implements Exception {
  McpValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'McpValidationException: ${errors.join(', ')}';
}
