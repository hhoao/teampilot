import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
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
}
