import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:teampilot_scheduler/teampilot_scheduler.dart';

void main() {
  final ctx = p.Context(style: p.Style.posix);
  final layout = SessionLayout(teampilotRoot: '/tp', pathContext: ctx);

  test('session runtime dir uses member segment when present', () {
    expect(
      layout.sessionRuntimeToolDir('w', 's', 'cursor', memberId: 'm1'),
      '/tp/workspace/workspaces/w/sessions/s/runtime/m1/cursor',
    );
    expect(
      layout.sessionRuntimeToolDir('w', 's', 'cursor'),
      '/tp/workspace/workspaces/w/sessions/s/runtime/cursor',
    );
  });

  test('cli cache global root is workspace/cache/cli/tool/provider', () {
    final cache = WorkspaceCliCache(layout: layout);
    expect(
      cache.globalRoot(tool: 'cursor', providerId: 'acct'),
      '/tp/workspace/cache/cli/cursor/acct',
    );
    expect(
      cache.globalRoot(tool: 'cursor', providerId: ''),
      '/tp/workspace/cache/cli/cursor/_shared',
    );
  });

  test('layout path formulas match workspace-storage-layout', () {
    expect(layout.cliDefaultsDir, '/tp/cli-defaults');
    expect(
      layout.identityToolDir('p1', 'cursor'),
      '/tp/identities-runtime/p1/cursor',
    );
    expect(
      layout.workspaceConfigToolDir('w', 'codex'),
      '/tp/workspace/workspaces/w/config/codex',
    );
  });

  test('bindingFor matches client CliTool lists; unknown is empty', () {
    expect(WorkspaceCliCache.bindingFor('cursor').map((b) => b.cacheRel), [
      'plugins/cache',
      'statsig-cache.json',
    ]);
    expect(WorkspaceCliCache.bindingFor('opencode').map((b) => b.cacheRel), [
      'package.json',
      'package-lock.json',
      'node_modules',
    ]);
    expect(WorkspaceCliCache.bindingFor('codex').map((b) => b.cacheRel), [
      'tmp-plugins',
      'plugins-cache',
    ]);
    expect(WorkspaceCliCache.bindingFor('claude'), isEmpty);
    expect(WorkspaceCliCache.bindingFor('flashskyai'), isEmpty);
    expect(WorkspaceCliCache.bindingFor('unknown-tool'), isEmpty);
  });
}
