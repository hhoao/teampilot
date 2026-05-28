import '../models/mcp_server.dart';
import '../services/mcp/mcp_catalog_service.dart';
import '../services/mcp/mcp_server_validator.dart';
import '../services/storage/app_storage.dart';
import '../services/storage/flashskyai_storage_roots.dart';

class McpRepository {
  McpRepository({
    FlashskyaiStorageRoots? storageRoots,
    McpCatalogService? catalog,
    McpServerValidator? validator,
  }) : _storageRoots = storageRoots,
       _catalog = catalog,
       _validator = validator ?? McpServerValidator();

  final FlashskyaiStorageRoots? _storageRoots;
  final McpCatalogService? _catalog;
  final McpServerValidator _validator;

  Future<McpCatalogService> _resolveCatalog() async {
    final injected = _catalog;
    if (injected != null) return injected;
    if (_storageRoots != null) {
      final roots = await _storageRoots.resolve();
      return McpCatalogService(catalogPath: roots.mcpServersJsonPath, fs: roots.fs);
    }
    return McpCatalogService(catalogPath: AppStorage.paths.mcpServersJson);
  }

  Future<List<McpServer>> loadAll() async {
    final catalog = await _resolveCatalog();
    return catalog.loadAll();
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
    return server;
  }

  Future<void> deleteById(String id) async {
    final catalog = await _resolveCatalog();
    await catalog.deleteById(id);
  }

  Future<McpCatalogService> catalogService() => _resolveCatalog();
}

class McpValidationException implements Exception {
  McpValidationException(this.errors);

  final List<String> errors;

  @override
  String toString() => 'McpValidationException: ${errors.join(', ')}';
}
