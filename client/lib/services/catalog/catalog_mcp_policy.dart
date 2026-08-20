import 'catalog_kind_registry.dart';
import 'catalog_mcp_constants.dart';

abstract final class CatalogMcpPolicy {
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
