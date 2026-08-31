import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  testWidgets(
    'right-tools toggle uses its explicit workspace while chat scope is stale',
    (tester) async {
      setUpTestAppStorage();
      addTearDown(tearDownTestAppStorage);

      final chat = testChatCubit(executableResolver: () => 'claude');
      final layout = LayoutCubit();
      final workbench = WorkbenchCubit()..enterLanding('landing-workspace');
      addTearDown(chat.close);
      addTearDown(layout.close);
      addTearDown(workbench.close);

      chat.setActiveWorkspace('previous-workspace');

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<ChatCubit>.value(value: chat),
            BlocProvider<LayoutCubit>.value(value: layout),
            BlocProvider<WorkbenchCubit>.value(value: workbench),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: WorkspaceShellRightToolsVisibilityToggle(
                workspaceId: 'landing-workspace',
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(AppKeys.rightToolsVisibilityButton));
      await tester.pump();

      expect(layout.state.landingRightToolsOverride, isTrue);
      expect(layout.state.preferences.rightToolsVisible, isFalse);
    },
  );
}
