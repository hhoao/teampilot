import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_agent_session_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('round-trips the agent session id', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    expect(await store.read(), isNull);
    await store.write('agent-9');
    expect(await store.read(), 'agent-9');
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('round-trips the session cwd', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    await store.write('agent-9', cwd: '/repo/.worktrees/feature');

    final record = await store.readRecord();
    expect(record?.sessionId, 'agent-9');
    expect(record?.cwd, '/repo/.worktrees/feature');
  });

  test('reads a legacy sidecar without a cwd', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    await fs.atomicWrite(
      '/tp/acp-session.json',
      '{"v":1,"sessionId":"agent-9"}',
    );

    final record = await store.readRecord();
    expect(record?.sessionId, 'agent-9');
    expect(record?.cwd, isNull);
  });

  test('omits an empty cwd from the sidecar', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    await store.write('agent-9', cwd: '   ');
    expect(
      await fs.readString('/tp/acp-session.json'),
      '{"v":1,"sessionId":"agent-9"}',
    );
    expect((await store.readRecord())?.cwd, isNull);
  });

  test('ignores a non-v1 or garbage file', () async {
    final fs = InMemoryFilesystem();
    final store = AcpAgentSessionStore(fs: fs, path: '/tp/acp-session.json');
    await fs.atomicWrite('/tp/acp-session.json', 'not json');
    expect(await store.read(), isNull);
  });
}
