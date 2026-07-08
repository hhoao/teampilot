import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_session_config_dir.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/cursor_warm_tier_manifest_paths.dart';
import '../../../support/in_memory_filesystem.dart';

void main() {
  test('mixed cursor member uses workspace team member home/.cursor as config root', () {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    final toolDir = layout.workspaceRuntimeMemberToolDir(
      'ws',
      cursorTestTeamId,
      'team-lead',
      'cursor',
    );

    expect(
      CursorSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws',
        sessionId: 'sess',
        memberId: 'team-lead',
        teamId: cursorTestTeamId,
      ),
      p.join(toolDir, 'home', '.cursor'),
    );
    expect(
      CursorSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws',
        sessionId: 'sess',
        memberId: 'team-lead',
        teamId: cursorTestTeamId,
      ),
      contains('/runtime/teams/$cursorTestTeamId/'),
    );
  });

  test('standalone cursor uses session toolDir/home/.cursor as config root', () {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    final toolDir = layout.sessionRuntimeToolDir('ws', 'sess', 'cursor');

    expect(
      CursorSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws',
        sessionId: 'sess',
      ),
      p.join(toolDir, 'home', '.cursor'),
    );
  });
}
