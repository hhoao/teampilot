import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lastWorkspace entry mode resolves workspace route', () {
    expect(
      workspaceEntryLocationFor(
        mode: WorkspaceEntryMode.lastWorkspace,
        lastOpenedWorkspaceId: 'proj-42',
      ),
      '/home-v2/workspace/proj-42',
    );
    expect(
      workspaceEntryLocationFor(
        mode: WorkspaceEntryMode.lastWorkspace,
        lastOpenedWorkspaceId: '',
      ),
      '/home-v2',
    );
  });

  test('legacy hub entry mode resolves to home', () {
    final prefs = LayoutPreferences.fromJson({
      'workspaceEntryMode': 'hub',
    });
    expect(prefs.workspaceEntryMode, WorkspaceEntryMode.home);
  });

  testWidgets('home workspace entry shows onboarding wizard on first run', (
    tester,
  ) async {
    addTearDown(() {
      appRouter.go('/home-v2');
    });

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final sessionPreferencesCubit = SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
    );
    final bootstrapCubit = AppBootstrapCubit()
      ..markAppReady(showOnboardingWizard: true);

    appRouter.go('/home-v2');

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettingsRepository>(
            create: (_) => InMemoryAppSettingsRepository(
              hasCompletedOnboarding: false,
            ),
          ),
          RepositoryProvider<ConnectionModeService>(
            create: (_) => ConnectionModeService(
              defaultTargetResolver: RuntimeTarget.local,
              hasSshProfiles: () => false,
            ),
          ),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bootstrapCubit),
            BlocProvider.value(value: sessionPreferencesCubit),
            BlocProvider(create: (_) => LayoutCubit()),
          ],
          child: MaterialApp.router(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: appRouter,
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(OnboardingWizard), findsOneWidget);

    await sessionPreferencesCubit.close();
    await bootstrapCubit.close();
  });
}
