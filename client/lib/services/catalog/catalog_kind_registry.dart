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

const _opPrefixes = <String, CatalogOp>{
  'search_': CatalogOp.search,
  'read_': CatalogOp.read,
  'install_': CatalogOp.install,
  'import_': CatalogOp.importPath,
  'create_': CatalogOp.create,
  'update_': CatalogOp.update,
  'unbind_': CatalogOp.unbind,
  'delete_': CatalogOp.delete,
};

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

  /// Exact advertised tool names plus [list_installed].
  Map<String, ({String kind, CatalogOp op})> _advertisedRoutes() {
    final map = <String, ({String kind, CatalogOp op})>{
      'list_installed': (kind: 'all', op: CatalogOp.list),
    };
    for (final module in _modules.values) {
      for (final tool in module.advertise()) {
        final op = _opFromAdvertisedName(tool.name);
        if (op == null) continue;
        map.putIfAbsent(tool.name, () => (kind: module.kind, op: op));
      }
    }
    return map;
  }

  Future<CatalogResult> dispatch(String toolName, CatalogRequest req) async {
    final parsed = _advertisedRoutes()[toolName];
    if (parsed == null) {
      throw CatalogException('unsupported_op', 'Unknown tool: $toolName');
    }

    if (toolName == 'list_installed') {
      return listInstalled(req);
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

  static CatalogOp? _opFromAdvertisedName(String toolName) {
    for (final entry in _opPrefixes.entries) {
      if (toolName.startsWith(entry.key)) return entry.value;
    }
    return null;
  }
}
