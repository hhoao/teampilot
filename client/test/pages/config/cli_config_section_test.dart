import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/config/cli_config_section.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(tearDownTestAppStorage);

  testWidgets('shows install button for Cursor CLI', (tester) async {
    late SessionPreferencesCubit cubit;

    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      cubit = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(prefs),
      );
      await cubit.load();
    });
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<ConnectionModeService>(
            create: (_) => ConnectionModeService(
              defaultTargetResolver: RuntimeTarget.local,
              hasSshProfiles: () => false,
            ),
          ),
        ],
        child: BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(
              body: CliConfigWorkspace(showHeading: false),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.opencodeCliInstallButton), findsOneWidget);
  });
}
