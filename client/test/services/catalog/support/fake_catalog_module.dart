import 'package:teampilot/services/catalog/catalog_kind.dart';

class FakeCatalogModule implements CatalogKindModule {
  FakeCatalogModule({required this.kind, this.supportsCreate = true});

  @override
  final String kind;
  @override
  final bool supportsCreate;
  @override
  bool get supportsImport => true;
  @override
  bool get supportsInstall => true;

  CatalogOp? lastOp;
  CatalogRequest? lastRequest;

  String get _searchName => kind == 'skill' ? 'search_skills' : 'search_$kind';

  @override
  List<CatalogToolSpec> advertise() => [
    CatalogToolSpec(
      name: _searchName,
      description: 'Search $kind',
      inputSchema: const {'type': 'object', 'properties': {}},
      mutating: false,
    ),
    if (supportsCreate)
      CatalogToolSpec(
        name: 'create_$kind',
        description: 'Create $kind',
        inputSchema: const {'type': 'object', 'properties': {}},
        mutating: true,
      ),
  ];

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) async {
    lastOp = op;
    lastRequest = req;
    if (op == CatalogOp.create && !supportsCreate) {
      throw CatalogException('unsupported_op', 'no create');
    }
    return CatalogResult.ok(
      kind: kind,
      ids: const ['x'],
      workspaceId: req.workspaceId,
    );
  }
}
