import 'catalog_kind.dart';
import 'catalog_kind_registry.dart';
import 'catalog_mcp_constants.dart';
import 'modules/mcp_catalog_tools.dart';
import 'modules/plugin_catalog_tools.dart';
import 'modules/skill_catalog_tools.dart';

/// Claude/Cursor allow-list policy for the teampilot catalog MCP.
///
/// Codex and OpenCode have no per-tool MCP allow list analogous to Claude
/// `permissions.allow` / Cursor `Mcp(server:tool)`. Enabling an MCP server
/// there auto-allows every tool on that server (Codex only has per-server
/// `default_tools_approval_mode`, which cannot split read vs mutate). Do not
/// invent a new allow file for those CLIs.
abstract final class CatalogMcpPolicy {
  /// Advertised catalog tools (same names as the live dispatch registry).
  ///
  /// Allow lists only need [CatalogKindModule.advertise]; app-shell owns the
  /// binder-backed dispatch instance.
  static CatalogKindRegistry advertisedRegistry() {
    return CatalogKindRegistry()
      ..register(const _AdvertisedKind('skill', skillCatalogTools))
      ..register(
        const _AdvertisedKind(
          'plugin',
          pluginCatalogTools,
          supportsCreate: false,
        ),
      )
      ..register(const _AdvertisedKind('mcp', mcpCatalogTools));
  }

  static List<String> readToolNames(CatalogKindRegistry registry) {
    return registry
        .allTools()
        .where((tool) => !tool.mutating)
        .map((tool) => tool.name)
        .toList();
  }

  static List<String> mutateToolNames(CatalogKindRegistry registry) {
    return registry
        .allTools()
        .where((tool) => tool.mutating)
        .map((tool) => tool.name)
        .toList();
  }

  static List<String> claudeAllowEntries(CatalogKindRegistry registry) {
    return readToolNames(registry)
        .map((name) => 'mcp__${catalogMcpServerName}__$name')
        .toList();
  }

  static List<String> cursorAllowEntries(CatalogKindRegistry registry) {
    return readToolNames(registry)
        .map((name) => 'Mcp($catalogMcpServerName:$name)')
        .toList();
  }
}

class _AdvertisedKind implements CatalogKindModule {
  const _AdvertisedKind(
    this.kind,
    this._tools, {
    this.supportsCreate = true,
  });

  @override
  final String kind;
  final List<CatalogToolSpec> _tools;
  @override
  final bool supportsCreate;
  @override
  bool get supportsImport => true;
  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => _tools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    throw UnsupportedError('advertised-only catalog kind');
  }
}
