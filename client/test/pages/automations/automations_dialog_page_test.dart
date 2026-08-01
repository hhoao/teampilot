import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/automation_list_scope.dart';
import 'package:teampilot/pages/automations/automations_dialog.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

import '../../support/post_frame_test_harness.dart';

Widget _wrap({
  required Widget child,
  required AutomationCubit automationCubit,
  required ChatCubit chatCubit,
}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return MultiBlocProvider(
    providers: [
      BlocProvider<AutomationCubit>.value(value: automationCubit),
      BlocProvider<ChatCubit>.value(value: chatCubit),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
        child: child,
      ),
    ),
  );
}

Future<void> _openAutomations(
  WidgetTester tester, {
  required Size viewport,
  required AutomationCubit automationCubit,
  required ChatCubit chatCubit,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _wrap(
      automationCubit: automationCubit,
      chatCubit: chatCubit,
      child: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              showAutomationsPanelDialog(
                context,
                listScope: AutomationListScope.workspace('ws1'),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('narrow: page presentation uses full-bleed PageShell', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await _openAutomations(
      tester,
      viewport: const Size(400, 800),
      automationCubit: setup.cubit,
      chatCubit: chatCubit,
    );

    final l10n = lookupAppLocalizations(const Locale('en'));

    expect(find.byType(TpDialogPageShell), findsOneWidget);
    expect(find.text(l10n.automationsTitle), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);

    final shellRect = tester.getRect(find.byType(TpDialogPageShell));
    expect(shellRect.width, closeTo(400, 0.5));
    expect(shellRect.height, closeTo(800, 0.5));
  });

  testWidgets('uses WorkspacePanePolicy narrow breakpoint for page path', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    final breakpoint = WorkspacePanePolicy.narrowBreakpointWidth;
    await _openAutomations(
      tester,
      viewport: Size(breakpoint - 1, 800),
      automationCubit: setup.cubit,
      chatCubit: chatCubit,
    );

    expect(find.byType(TpDialogPageShell), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('wide: desktop PageShell header (not mobile nav)', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    addTearDown(chatCubit.close);

    await _openAutomations(
      tester,
      viewport: const Size(1200, 800),
      automationCubit: setup.cubit,
      chatCubit: chatCubit,
    );

    expect(find.byType(TpDialogPageShell), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(TpDialogHeader), findsOneWidget);
    expect(find.byType(TpDialogMobileNavBar), findsNothing);
  });
}
