import 'package:teampilot/models/automation_tab_scope.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/automation_state.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../support/post_frame_test_harness.dart';

final _session = AppSession(
  sessionId: 'sess-1',
  workspaceId: 'ws1',
  createdAt: 1,
  updatedAt: 1,
);

Automation _sessionAutomation() {
  return Automation(
    id: 'auto-1',
    name: 'Ping',
    action: AutomationAction.scheduledMessage,
    workspaceId: 'ws1',
    launchProfileId: AutomationTabScope.simpleLaunchProfileId,
    sessionId: 'sess-1',
    message: 'hello',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

Widget _host({
  required ChatCubit chatCubit,
  required AutomationCubit automationCubit,
  required SessionRepository sessionRepository,
  Widget? child,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiRepositoryProvider(
      providers: [
        RepositoryProvider<SessionRepository>.value(value: sessionRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<ChatCubit>.value(value: chatCubit),
          BlocProvider<AutomationCubit>.value(value: automationCubit),
        ],
        child: Scaffold(
          body:
              child ??
              SidebarSessionTile(
                session: _session,
                launchProfileId: AutomationTabScope.simpleLaunchProfileId,
                onTap: () {},
              ),
        ),
      ),
    ),
  );
}

Future<void> _openContextMenu(WidgetTester tester) async {
  await tester.tap(
    find.byType(SidebarSessionTile),
    buttons: kSecondaryMouseButton,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _dismissContextMenu(WidgetTester tester) async {
  // Tap the modal barrier to close the popup menu overlay.
  await tester.tapAt(const Offset(1, 1));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('context menu includes scheduled message action', (tester) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final automationCubit = testAutomationCubit();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile)),
    );
    expect(find.text(l10n.automationsSessionContextMenu), findsOneWidget);

    await _dismissContextMenu(tester);
  });

  testWidgets('context menu shows manage item when session has automations', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final automationCubit = testAutomationCubit();
    addTearDown(chatCubit.close);
    addTearDown(automationCubit.close);

    automationCubit.emit(
      AutomationState(
        automations: [_sessionAutomation()],
        status: AutomationLoadStatus.ready,
      ),
    );

    await tester.pumpWidget(
      _host(
        chatCubit: chatCubit,
        automationCubit: automationCubit,
        sessionRepository: SessionRepository(),
      ),
    );
    await tester.pump();

    await _openContextMenu(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile)),
    );
    expect(find.text(l10n.automationsSessionContextMenu), findsOneWidget);
    expect(find.text(l10n.automationsManageSessionContextMenu), findsOneWidget);

    await _dismissContextMenu(tester);
  });
}
