import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_policy.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

class _FakeModule implements CatalogKindModule {
  _FakeModule({required this.kind, this.supportsCreate = true});

  @override
  final String kind;
  @override
  final bool supportsCreate;
  @override
  bool get supportsImport => true;
  @override
  bool get supportsInstall => true;

  @override
  List<CatalogToolSpec> advertise() => [
    CatalogToolSpec(
      name: 'search_$kind',
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

void main() {
  final fs = LocalFilesystem();
  CatalogRequest req() => CatalogRequest(
    sessionId: 's',
    workspaceId: 'w',
    arguments: const {},
    workFs: fs,
    allowedRoots: const ['/work'],
  );

  test('omits create_plugin when supportsCreate is false', () {
    final registry = CatalogKindRegistry()
      ..register(_FakeModule(kind: 'skill'))
      ..register(_FakeModule(kind: 'plugin', supportsCreate: false));
    final names = registry.allTools().map((t) => t.name).toList();
    expect(names, contains('list_installed'));
    expect(names, contains('search_skill'));
    expect(names, contains('create_skill'));
    expect(names, contains('search_plugin'));
    expect(names, isNot(contains('create_plugin')));
  });

  test('policy splits read and mutate tools', () {
    final registry = CatalogKindRegistry()
      ..register(_FakeModule(kind: 'skill'));
    expect(CatalogMcpPolicy.readToolNames(registry), contains('search_skill'));
    expect(CatalogMcpPolicy.readToolNames(registry), contains('list_installed'));
    expect(
      CatalogMcpPolicy.mutateToolNames(registry),
      contains('create_skill'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      contains('mcp__teampilot__search_skill'),
    );
    expect(
      CatalogMcpPolicy.cursorAllowEntries(registry),
      contains('Mcp(teampilot:search_skill)'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      isNot(contains('mcp__teampilot__create_skill')),
    );
  });

  test('dispatch routes install_skill to skill module install op', () async {
    final registry = CatalogKindRegistry()..register(_FakeModule(kind: 'skill'));
    final result = await registry.dispatch('create_skill', req());
    expect(result.ids, ['x']);
    expect(result.restartRequired, isTrue);
  });
}
