import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/launch/session_launch_host.dart';
import 'package:teampilot/services/chat/launch/connect/session_shell_connector.dart';

import '../../../support/fake_terminal_session.dart';
import '../../../support/in_memory_filesystem.dart';
import '../../../support/test_session_persistence_writer.dart';

void main() {
  late ChatTabStore tabStore;
  late _Host host;
  late SessionShellConnector connector;
  late FakeTerminalSession shell;

  setUp(() {
    tabStore = ChatTabStore(storage: fakeHomeStorage());
    host = _Host(tabStore);
    connector = SessionShellConnector(
      host,
      _Delegate(),
      persister: inertSessionPersistenceWriter(),
      isLocalNative: () => true,
    );
    shell = FakeTerminalSession(fs: InMemoryFilesystem());
  });

  tearDown(() => shell.dispose());

  test('stillValid is true only while the session tab is open', () {
    expect(
      connector.connectShellStillValid(sessionId: 'sess-1', shell: shell),
      isFalse,
    );

    tabStore.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'T', subtitle: ''),
        cliTeamName: '',
      ),
    );

    expect(
      connector.connectShellStillValid(sessionId: 'sess-1', shell: shell),
      isTrue,
    );
  });

  test('abort finishes a connecting session when the tab is gone', () {
    host.connecting.add('sess-1');

    connector.abortConnectShellIfStale(
      sessionId: 'sess-1',
      shell: shell,
      reason: 'tab_gone',
    );

    expect(host.finished, ['sess-1']);
  });

  test('abort is a no-op while the session tab is still open', () {
    tabStore.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess-1', title: 'T', subtitle: ''),
        cliTeamName: '',
      ),
    );
    host.connecting.add('sess-1');

    connector.abortConnectShellIfStale(
      sessionId: 'sess-1',
      shell: shell,
      reason: 'should_not_fire',
    );

    expect(host.finished, isEmpty);
  });
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  bool isClosed = false;

  final connecting = <String>{};
  final finished = <String>[];

  @override
  bool isSessionConnecting(String sessionId) => connecting.contains(sessionId);

  @override
  void finishSessionConnect(String sessionId) => finished.add(sessionId);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Delegate implements SessionShellConnectorDelegate {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
