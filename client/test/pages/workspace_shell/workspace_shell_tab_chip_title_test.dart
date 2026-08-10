import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('session tab paints New Chat fallback while display is empty', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    chatCubit.applyState(
      chatCubit.state.copyWith(
        sessions: [
          AppSession(
            sessionId: 'sess-1',
            workspaceId: 'ws1',
            createdAt: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            scale: 1.0,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<AgentAttentionCubit>.value(value: attention),
            ],
            child: Scaffold(
              body: WorkbenchStripTabChip(
                title: '',
                active: true,
                sessionId: 'sess-1',
                tabId: 'sess-1',
                kind: WorkbenchTabKind.session,
                onTap: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New Chat'), findsOneWidget);
  });
}
