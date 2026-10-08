import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/session.dart';
import 'package:teampilot/services/cli/cursor/capabilities/session_lifecycle.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/noop_cli_session_capability.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('no-op gateConnect always allows', () {
    const cap = NoopCliSessionCapability();
    expect(
      cap
          .gateConnect(
            const CliSessionGateContext(
              workspaceId: 'w',
              sessionId: 's',
              memberId: 'm',
              tool: CliTool.claude,
            ),
          )
          .allowed,
      isTrue,
    );
  });

  test('no-op session config dir delegates to DefaultCliConfigLayout', () {
    const cap = NoopCliSessionCapability();
    final layout = RuntimeLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );
    expect(
      cap.sessionConfigDir(
        layout,
        CliTool.claude,
        workspaceId: 'w',
        sessionId: 's',
      ),
      layout.sessionRuntimeToolDir('w', 's', CliTool.claude.value),
    );
  });

  test('cursor session capability exposes isolated home root', () {
    const cap = CursorSessionLifecycleCapability();
    final layout = RuntimeLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );
    expect(
      cap.sessionIsolatedHomeRoot(
        layout,
        CliTool.cursor,
        workspaceId: 'w',
        sessionId: 's',
        memberId: 'm1',
      ),
      layout.pathContext.join(
        layout.sessionRuntimeToolDir(
          'w',
          's',
          CliTool.cursor.value,
          memberId: 'm1',
        ),
        'home',
      ),
    );
    expect(
      cap.sessionIsolatedHomeRoot(
        layout,
        CliTool.cursor,
        workspaceId: 'w',
        sessionId: 's',
      ),
      layout.pathContext.join(
        layout.sessionRuntimeToolDir('w', 's', CliTool.cursor.value),
        'home',
      ),
    );
  });

  test('claude session capability resolves member hook settings path', () {
    const cap = ClaudeCliSessionCapability();
    final layout = RuntimeLayout(
      teampilotRoot: '/tp',
      fs: InMemoryFilesystem(),
    );
    final ctx = layout.pathContext;
    const toolDir = '/tp/w/s/runtime/claude';
    final paths = cap.hookMaterializationPaths(
      pathContext: ctx,
      memberToolDir: toolDir,
      member: const TeamMemberConfig(
        id: 'member/a',
        name: 'n',
        agent: 'a',
      ),
    );
    expect(paths.hooksDir, ctx.join(toolDir, 'hooks'));
    expect(
      paths.configPath,
      ctx.join(toolDir, 'settings', 'member-a.json'),
    );
  });
}
