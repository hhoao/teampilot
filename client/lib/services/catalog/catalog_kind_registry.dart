import 'catalog_kind.dart';

const _listInstalledTool = CatalogToolSpec(
  name: 'list_installed',
  description: 'List installed catalog entries by kind',
  inputSchema: {
    'type': 'object',
    'properties': {
      'kind': {'type': 'string'},
    },
    'required': ['kind'],
  },
  mutating: false,
);

class CatalogKindRegistry {
  final _modules = <String, CatalogKindModule>{};

  void register(CatalogKindModule module) {
    _modules[module.kind] = module;
  }

  CatalogKindModule? module(String kind) => _modules[kind];

  List<CatalogToolSpec> allTools() {
    final tools = <CatalogToolSpec>[_listInstalledTool];
    for (final module in _modules.values) {
      tools.addAll(module.advertise());
    }
    return tools;
  }

  Future<CatalogResult> dispatch(String toolName, CatalogRequest req) async {
    if (toolName == 'list_installed') {
      return listInstalled(req);
    }

    final parsed = _parseToolName(toolName);
    if (parsed == null) {
      throw CatalogException('unsupported_op', 'Unknown tool: $toolName');
    }

    final module = _modules[parsed.kind];
    if (module == null) {
      throw CatalogException(
        'unsupported_op',
        'No module registered for kind: ${parsed.kind}',
      );
    }

    return module.handle(parsed.op, req);
  }

  Future<CatalogResult> listInstalled(CatalogRequest req) async {
    final merged = <String, Object?>{};
    for (final module in _modules.values) {
      final result = await module.handle(CatalogOp.list, req);
      if (result.data != null) {
        merged.addAll(result.data!);
      }
    }
    return CatalogResult.ok(
      kind: 'all',
      ids: const [],
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: merged,
    );
  }

  ({CatalogOp op, String kind})? _parseToolName(String toolName) {
    const opNames = {
      'search': CatalogOp.search,
      'read': CatalogOp.read,
      'install': CatalogOp.install,
      'import': CatalogOp.importPath,
      'create': CatalogOp.create,
      'update': CatalogOp.update,
      'unbind': CatalogOp.unbind,
      'delete': CatalogOp.delete,
    };

    for (final entry in opNames.entries) {
      final prefix = '${entry.key}_';
      if (toolName.startsWith(prefix)) {
        return (op: entry.value, kind: toolName.substring(prefix.length));
      }
    }
    return null;
  }
}
