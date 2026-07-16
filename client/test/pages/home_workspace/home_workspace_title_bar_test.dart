import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late ChatCubit chatCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
  });
  tearDown(() async {
    if (!chatCubit.isClosed) {
      await chatCubit.close();
    }
    tearDownTestAppStorage();
  });

  testWidgets('title bar renders workspace tabs', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider(create: (_) => NotificationCubit()),
            BlocProvider(create: (_) => LayoutCubit()),
          ],
          child: const HomeTitleBar(
            tabs: [
              HomeWorkspaceTab(id: 'ws-a', name: 'Solo'),
              HomeWorkspaceTab(id: 'ws-b', name: 'Shared'),
            ],
            activeTabKey: 'ws-a',
          ),
        ),
      ),
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(HomeTitleBar), findsOneWidget);
    expect(find.byType(WorkspaceShellPaneVisibilityToggles), findsOneWidget);
    expect(find.byKey(AppKeys.sidebarVisibilityButton), findsOneWidget);
    expect(find.byKey(AppKeys.rightToolsVisibilityButton), findsOneWidget);
  });

  testWidgets('pane visibility toggles hidden on home view', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chatCubit),
            BlocProvider(create: (_) => NotificationCubit()),
            BlocProvider(create: (_) => LayoutCubit()),
          ],
          child: const HomeTitleBar(
            tabs: [
              HomeWorkspaceTab(id: 'ws-a', name: 'Solo'),
            ],
            activeTabKey: null,
          ),
        ),
      ),
    );

    expect(find.byType(WorkspaceShellPaneVisibilityToggles), findsNothing);
  });
}
