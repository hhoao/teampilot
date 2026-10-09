import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/chat/launch/connect/session_connect_job.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/session_open_request.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  test('attachAcpRuntime requires session.cli instead of defaulting', () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    tabStore.registerSession(
      ChatTab(
        info: ChatTabInfo(id: 's1', title: 'S', subtitle: ''),
        cliTeamName: '',
      ),
    );
    final service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
    );
    final session = AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      acp: true,
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'w1', createdAt: 1);
    final job = SessionConnectJob(
      session: session,
      request: SessionOpenRequest(session: session, workspace: workspace),
      generation: 1,
      workspace: workspace,
      reason: LaunchReason.create,
    );

    await expectLater(
      service.attachAcpRuntime(job, session),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'ACP session requires session.cli',
        ),
      ),
    );
  });
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}
