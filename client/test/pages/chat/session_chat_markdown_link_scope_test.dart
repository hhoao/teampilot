import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/session_chat_markdown_link_scope.dart';

void main() {
  setUp(() {
    _LinkActionsProbe.builds = 0;
  });

  testWidgets(
    'parent rebuild does not notify markdown link dependents',
    (tester) async {
      late StateSetter setParentState;
      final session = _session();
      final workspace = _workspace();

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setParentState = setState;
              return SessionChatMarkdownLinkScope(
                session: session,
                workspace: workspace,
                selectedMemberId: 'm1',
                hrefRoots: const ['/repo'],
                child: const _LinkActionsProbe(),
              );
            },
          ),
        ),
      );

      expect(_LinkActionsProbe.builds, 1);
      setParentState(() {});
      await tester.pump();
      expect(_LinkActionsProbe.builds, 1);
    },
  );

  testWidgets(
    'new AiMarkdownLinkActions instance notifies dependents',
    (tester) async {
      late StateSetter setParentState;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              setParentState = setState;
              return AiMarkdownLinkActionsScope(
                actions: AiMarkdownLinkActions(
                  onLinkTap: (href) async {},
                ),
                child: const _LinkActionsProbe(),
              );
            },
          ),
        ),
      );

      expect(_LinkActionsProbe.builds, 1);
      setParentState(() {});
      await tester.pump();
      expect(_LinkActionsProbe.builds, 2);
    },
  );
}

AppSession _session() => AppSession(
  sessionId: 'sess-1',
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp')],
  createdAt: 1,
  updatedAt: 1,
);

Workspace _workspace() => Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp')],
  createdAt: 1,
);

class _LinkActionsProbe extends StatelessWidget {
  const _LinkActionsProbe();

  static int builds = 0;

  @override
  Widget build(BuildContext context) {
    AiMarkdownLinkActions.of(context);
    builds++;
    return const SizedBox.shrink();
  }
}
