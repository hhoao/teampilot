import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_policy.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import 'support/fake_catalog_module.dart';

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
      ..register(FakeCatalogModule(kind: 'skill'))
      ..register(FakeCatalogModule(kind: 'plugin', supportsCreate: false));
    final names = registry.allTools().map((t) => t.name).toList();
    expect(names, contains('list_installed'));
    expect(names, contains('search_skills'));
    expect(names, contains('create_skill'));
    expect(names, contains('search_plugin'));
    expect(names, isNot(contains('create_plugin')));
  });

  test('policy splits read and mutate tools', () {
    final registry = CatalogKindRegistry()
      ..register(FakeCatalogModule(kind: 'skill'));
    expect(CatalogMcpPolicy.readToolNames(registry), contains('search_skills'));
    expect(
      CatalogMcpPolicy.readToolNames(registry),
      contains('list_installed'),
    );
    expect(
      CatalogMcpPolicy.mutateToolNames(registry),
      contains('create_skill'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      contains('mcp__teampilot__search_skills'),
    );
    expect(
      CatalogMcpPolicy.cursorAllowEntries(registry),
      contains('Mcp(teampilot:search_skills)'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      isNot(contains('mcp__teampilot__create_skill')),
    );
  });

  test('dispatch routes install_skill to skill module install op', () async {
    final registry = CatalogKindRegistry()
      ..register(FakeCatalogModule(kind: 'skill'));
    final result = await registry.dispatch('create_skill', req());
    expect(result.ids, ['x']);
    expect(result.restartRequired, isTrue);
  });

  test('dispatch maps advertised search_skills to skill search', () async {
    final skill = FakeCatalogModule(kind: 'skill');
    final registry = CatalogKindRegistry()..register(skill);
    final result = await registry.dispatch('search_skills', req());
    expect(result.ids, ['x']);
    expect(skill.lastOp, CatalogOp.search);
  });
}
