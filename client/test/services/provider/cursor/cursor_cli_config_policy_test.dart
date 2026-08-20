import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_kind_registry.dart';
import 'package:teampilot/services/catalog/catalog_mcp_policy.dart';
import 'package:teampilot/services/catalog/modules/skill_catalog_tools.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_cli_config_policy.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_config.dart';

void main() {
  test('teamBusMcpAllowEntry uses teammate-bus server wildcard', () {
    expect(
      CursorCliConfigPolicy.teamBusMcpAllowEntry,
      'Mcp($teammateBusMcpServerName:*)',
    );
  });

  test(
    'applyMixedTeamSessionPolicy adds Mcp allow without clobbering auth',
    () {
      const input = {
        'version': 1,
        'authInfo': {'userId': 'u1'},
        'permissions': {
          'allow': ['Shell(ls)'],
          'deny': [],
        },
      };
      final merged = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(input);
      final allow = (merged['permissions']! as Map)['allow'] as List;
      expect(allow, contains('Shell(ls)'));
      expect(allow, contains(CursorCliConfigPolicy.teamBusMcpAllowEntry));
      expect(merged['authInfo'], isNotNull);
    },
  );

  test('applyMixedTeamSessionPolicy is idempotent', () {
    final once = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(const {});
    final twice = CursorCliConfigPolicy.applyMixedTeamSessionPolicy(once);
    final allow = (twice['permissions']! as Map)['allow'] as List;
    expect(
      allow
          .where((e) => e == CursorCliConfigPolicy.teamBusMcpAllowEntry)
          .length,
      1,
    );
  });

  test('applyCatalogReadPolicy allows catalog reads not installs', () {
    final entries = CursorCliConfigPolicy.catalogReadAllowEntries(
      CatalogMcpPolicy.cursorAllowEntries(_skillRegistry()),
    );
    final merged = CursorCliConfigPolicy.applyCatalogReadPolicy(
      const {},
      cursorEntries: entries,
    );
    final allow = (merged['permissions']! as Map)['allow'] as List;
    expect(allow, contains('Mcp(teampilot:search_skills)'));
    expect(allow, isNot(contains('Mcp(teampilot:install_skill)')));
  });
}

CatalogKindRegistry _skillRegistry() {
  return CatalogKindRegistry()..register(_SkillAdvertiseModule());
}

class _SkillAdvertiseModule implements CatalogKindModule {
  @override
  String get kind => 'skill';
  @override
  bool get supportsCreate => true;
  @override
  bool get supportsImport => true;
  @override
  bool get supportsInstall => true;
  @override
  List<CatalogToolSpec> advertise() => skillCatalogTools;
  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    throw UnsupportedError('advertise-only');
  }
}
