import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_bootstrap_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/ssh_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';

import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

Workspace _workspace(String id) =>
    Workspace(workspaceId: id, folders: const [], display: id, createdAt: 1);

void _ingest(ChatCubit chatCubit, List<String> ids) {
  chatCubit.ingestWorkspaceSessionSnapshot(
    workspaces: [for (final id in ids) _workspace(id)],
    sessions: const [],
  );
}

/// Mounts the app router with onboarding still showing, so only the routing
/// layer runs (the workspace shell needs the full production provider graph).
Future<void> _pumpRouter(WidgetTester tester, ChatCubit chatCubit) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
  );
  final bootstrapCubit = AppBootstrapCubit()
    ..markAppReady(showOnboardingWizard: true);
  final sshProfileCubit = SshProfileCubit(
    profileRepository: SshProfileRepository(
      rootDir: '/tmp/home_workspace_redirect_ssh_fake',
      fs: InMemoryFilesystem(),
      storage: fakeHomeStorage(),
    ),
    credentialStore: InMemorySshCredentialStore(),
  );
  addTearDown(sshProfileCubit.close);
  addTearDown(sessionPreferencesCubit.close);
  addTearDown(bootstrapCubit.close);

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
          BlocProvider.value(value: chatCubit),
          BlocProvider(create: (_) => LayoutCubit()),
        ],
        child: MaterialApp.router(
          theme: theme,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: appLocalizationsSupportedLocales,
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatCubit chatCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    chatCubit = testChatCubit(executableResolver: () => 'cli-not-installed');
    addTearDown(() => appRouter.go('/home-v2'));
    addTearDown(chatCubit.close);
  });

  testWidgets(
    'a workspace route missing from the home index redirects to home',
    (tester) async {
      _ingest(chatCubit, const ['ws-in-this-home']);
      appRouter.go('/home-v2');
      await _pumpRouter(tester, chatCubit);

      // Restored from device-local preferences but not in this home's index:
      // the workspace tab would render an empty body.
      appRouter.go('/home-v2/workspace/ws-from-another-home');
      await tester.pump();

      expect(
        appRouter.routerDelegate.currentConfiguration.uri.path,
        '/home-v2',
      );
    },
  );

  testWidgets(
    'the index landing re-runs the redirect for a restored workspace route',
    (tester) async {
      // Cold start while the home plane was unreachable: the entry mode restore
      // ran against an empty index, so the route is allowed to wait.
      applyWorkspaceEntryMode(
        WorkspaceEntryMode.lastWorkspace,
        lastOpenedWorkspaceId: 'ws-from-another-home',
      );
      appRouter.go('/home-v2/workspace/ws-from-another-home');
      await _pumpRouter(tester, chatCubit);
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.path,
        '/home-v2/workspace/ws-from-another-home',
      );

      // The home connects and its index lands: the restored id does not exist
      // there. The entry reapply refreshes the router, whose redirect sends the
      // stale route home instead of leaving an empty body.
      _ingest(chatCubit, const ['ws-in-this-home']);
      reapplyWorkspaceEntryFromPreferences(
        const LayoutPreferences(
          workspaceEntryMode: WorkspaceEntryMode.lastWorkspace,
          lastOpenedWorkspaceId: 'ws-from-another-home',
        ),
        knownWorkspaceIds: const {'ws-in-this-home'},
      );
      await tester.pump();

      expect(
        appRouter.routerDelegate.currentConfiguration.uri.path,
        '/home-v2',
      );
    },
  );
}
