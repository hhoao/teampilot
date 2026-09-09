import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/config/session_config_section.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/storage/runtime_target_registry.dart';
import 'package:teampilot/services/storage/targets_repository.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('auto-fetch switch toggles and interval dropdown persists', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final cubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    addTearDown(cubit.close);
    await cubit.load();

    final fs = InMemoryFilesystem();
    const root = '/tp';
    var currentId = 'local';
    final controller = HomeTargetController(
      registry: RuntimeTargetRegistry(
        repo: TargetsRepository(rootDir: root, fs: fs),
        sshProfileRepo: SshProfileRepository(rootDir: root, fs: fs),
        isWindows: false,
        isAndroid: false,
      ),
      current: () => RuntimeTarget(
        id: currentId,
        label: currentId,
        kind: runtimeKindOfId(currentId),
      ),
      switchTo: (id) async {
        currentId = id;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ConnectionModeService>(
              create: (_) => ConnectionModeService(
                defaultTargetResolver: RuntimeTarget.local,
                hasSshProfiles: () => false,
              ),
            ),
            RepositoryProvider<HomeTargetController>.value(value: controller),
          ],
          child: Scaffold(
            body: BlocProvider<SessionPreferencesCubit>.value(
              value: cubit,
              child: const SessionConfigWorkspace(showHeading: false),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(cubit.state.preferences.gitAutoFetchEnabled, isTrue);
    expect(cubit.state.preferences.gitAutoFetchIntervalMinutes, 5);

    // Locate the switch via the row title (other switches exist on this page).
    final fetchRow = find.ancestor(
      of: find.text('Auto-fetch remote updates'),
      matching: find.byType(TpPreferenceRow),
    );
    expect(fetchRow, findsOneWidget);
    final fetchSwitch = find.descendant(
      of: fetchRow,
      matching: find.byType(Switch),
    );
    expect(fetchSwitch, findsOneWidget);

    await tester.ensureVisible(fetchSwitch);
    await tester.pumpAndSettle();
    await tester.tap(fetchSwitch);
    await tester.pumpAndSettle();
    expect(cubit.state.preferences.gitAutoFetchEnabled, isFalse);

    final intervalRow = find.ancestor(
      of: find.text('Auto-fetch interval (minutes)'),
      matching: find.byType(TpPreferenceRow),
    );
    expect(intervalRow, findsOneWidget);
    final intervalDropdown = find.descendant(
      of: intervalRow,
      matching: find.byType(DropdownButton<int>),
    );
    expect(intervalDropdown, findsOneWidget);

    await tester.ensureVisible(intervalDropdown);
    await tester.pumpAndSettle();
    await tester.tap(intervalDropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every 15 min').last);
    await tester.pumpAndSettle();
    expect(cubit.state.preferences.gitAutoFetchIntervalMinutes, 15);
  });
}
