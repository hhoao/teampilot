import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/provider/cursor/cursor_session_config_dir.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('mixed cursor member uses toolDir/home/.cursor as config root', () {
    final fs = InMemoryFilesystem();
    final layout = RuntimeLayout(teampilotRoot: '/tp', fs: fs);
    final toolDir = layout.sessionRuntimeToolDir(
      'ws',
      'sess',
      'cursor',
      memberId: 'team-lead',
    );

    expect(
      CursorSessionConfigDir.resolve(
        layout,
        workspaceId: 'ws',
        sessionId: 'sess',
        memberId: 'team-lead',
      ),
      p.join(toolDir, 'home', '.cursor'),
    );
  });

  test('standalone cursor uses toolDir/home/.cursor as config root', () {
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
