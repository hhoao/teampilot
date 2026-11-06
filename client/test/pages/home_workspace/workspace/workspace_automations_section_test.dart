import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_automations_section.dart';
import 'package:teampilot/services/storage/app_paths.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/post_frame_test_harness.dart';

Widget _wrap(AutomationCubit cubit, Widget child) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return BlocProvider<AutomationCubit>.value(
    value: cubit,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    // The section loads its workspace scope unawaited on mount. An in-memory
    // home lets that read resolve under fake async, so the assertion below
    // genuinely covers the mount-time load instead of re-issuing it.
    installTestHomeStorage(
      filesystem: InMemoryFilesystem(
        pathContext: p.Context(style: p.Style.posix),
      ),
      paths: const AppPaths('/tp-test-section'),
    );
  });
  tearDown(tearDownTestAppStorage);

  testWidgets('renders the scheduled-tasks pill without stats or add action', (
    tester,
  ) async {
    final setup = testAutomationSetup();
    addTearDown(setup.cubit.close);
    await setup.repo.upsert(
      Automation(
        id: 'a1',
        name: 'Morning ping',
        action: AutomationAction.scheduledMessage,
        workspaceId: 'ws1',
        sessionId: 'sess-1',
        message: 'ping',
        preset: AutomationSchedulePreset.daily,
        hourMinute: '09:00',
        timezone: 'UTC',
        dtstartMs: 1,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    );

    await tester.pumpWidget(
      _wrap(
        setup.cubit,
        WorkspaceAutomationsSection(
          workspace: Workspace(workspaceId: 'ws1', createdAt: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.alarm_rounded), findsOneWidget);
    expect(find.text('Scheduled tasks'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(setup.cubit.state.automations.map((a) => a.id), contains('a1'));
  });
}
