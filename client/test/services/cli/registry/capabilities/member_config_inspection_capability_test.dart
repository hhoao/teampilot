import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/registry/capabilities/member_config_inspection_capability.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  const cap = DefaultMemberConfigInspection();

  setUp(() => fs = InMemoryFilesystem());

  MemberConfigContext ctx() => MemberConfigContext(
        cli: CliTool.claude,
        configDir: '/cfg',
        sourceLayer: MemberConfigSourceLayer.runtime,
        mcpSnapshotPath: '/mcp/servers.json',
        provider: 'anthropic',
        model: 'claude-opus-4-8',
        fs: fs,
      );

  test('reads skills from skills/ subdirectories', () async {
    await fs.writeString(
      '/cfg/skills/alpha/SKILL.md',
      '---\nname: Alpha\ndescription: does alpha\n---\nbody',
    );
    await fs.ensureDir('/cfg/skills/beta');

    final detail = await cap.inspect(ctx());

    expect(detail.skills.map((s) => s.name).toList()..sort(),
        ['Alpha', 'beta']);
    final alpha = detail.skills.firstWhere((s) => s.name == 'Alpha');
    expect(alpha.description, 'does alpha');
  });

  test('reads plugins from plugins/ via manifest', () async {
    await fs.writeString(
      '/cfg/plugins/p1/.claude-plugin/plugin.json',
      '{"name":"p1","version":"1.2.0"}',
    );

    final detail = await cap.inspect(ctx());

    expect(detail.plugins, hasLength(1));
    expect(detail.plugins.single.name, 'p1');
    expect(detail.plugins.single.version, '1.2.0');
  });

  test('reads MCP servers from the snapshot file', () async {
    await fs.writeString(
      '/mcp/servers.json',
      '{"mcpServers":{"fs":{"command":"npx","args":["server-fs"]},'
      '"web":{"url":"https://example.com/mcp"}}}',
    );

    final detail = await cap.inspect(ctx());

    expect(detail.mcpServers.map((m) => m.name).toList()..sort(),
        ['fs', 'web']);
    final web = detail.mcpServers.firstWhere((m) => m.name == 'web');
    expect(web.summary, contains('https://example.com/mcp'));
  });

  test('reads flat settings from settings.json', () async {
    await fs.writeString(
      '/cfg/settings.json',
      '{"theme":"dark","autoUpdate":true}',
    );

    final detail = await cap.inspect(ctx());

    final keys = detail.settings.map((e) => e.key).toList()..sort();
    expect(keys, ['autoUpdate', 'theme']);
  });

  test('missing directories yield empty sections without warnings', () async {
    final detail = await cap.inspect(ctx());
    expect(detail.skills, isEmpty);
    expect(detail.plugins, isEmpty);
    expect(detail.mcpServers, isEmpty);
    expect(detail.settings, isEmpty);
    expect(detail.warnings, isEmpty);
  });

  test('corrupt settings.json produces a section warning, not a throw', () async {
    await fs.writeString('/cfg/settings.json', '{not json');
    final detail = await cap.inspect(ctx());
    expect(detail.settings, isEmpty);
    expect(detail.warnings.map((w) => w.section), contains('settings'));
  });
}
