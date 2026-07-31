import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/onboarding/onboarding_wizard.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

import '../support/in_memory_filesystem.dart';

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
    final prefs = LayoutPreferences.fromJson({'workspaceEntryMode': 'hub'});
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
    final sshProfileCubit = SshProfileCubit(
      profileRepository: SshProfileRepository(
        rootDir: '/tmp/onboarding_gate_ssh_fake',
        fs: InMemoryFilesystem(),
      ),
      credentialStore: InMemorySshCredentialStore(),
    );
    addTearDown(sshProfileCubit.close);

    appRouter.go('/home-v2');

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<AppSettingsRepository>(
            create: (_) =>
                InMemoryAppSettingsRepository(hasCompletedOnboarding: false),
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
            BlocProvider.value(value: sshProfileCubit),
            BlocProvider(create: (_) => LayoutCubit()),
          ],
          child: MaterialApp.router(
            theme: theme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: appRouter,
            builder: (context, child) => TpTheme(
              data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(OnboardingWizard), findsOneWidget);

    await sessionPreferencesCubit.close();
    await bootstrapCubit.close();
  });
}
