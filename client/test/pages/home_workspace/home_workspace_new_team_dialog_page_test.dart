import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team/model/launch_profile_state.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_new_team_dialog.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

import '../../support/post_frame_test_harness.dart';

class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit() {
    emit(const AppProviderState());
  }
}

LaunchProfileCubit _launchCubit() {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('new_team_dialog_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'claude',
  );
  cubit.applyState(const LaunchProfileState(isLoading: false));
  return cubit;
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('wide: desktop header and shrink-wrap (no mobile chevron)', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final teamCubit = _launchCubit();
    addTearDown(teamCubit.close);
    final presets = CliPresetsCubit(
      repository: CliPresetsRepository(
        fs: AppStorage.fs,
        presetsPath: '${AppStorage.paths.basePath}/cli-presets.json',
      ),
    );
    addTearDown(presets.close);
    final ai = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    addTearDown(ai.close);
    final providers = _SeededAppProviderCubit();
    addTearDown(providers.close);

    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<LaunchProfileCubit>.value(value: teamCubit),
          BlocProvider<AiFeatureSettingsCubit>.value(value: ai),
          BlocProvider<AppProviderCubit>.value(value: providers),
          BlocProvider<CliPresetsCubit>.value(value: presets),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            colorScheme: scheme,
            useMaterial3: true,
            dialogTheme: buildTpDialogTheme(
              colorScheme: scheme,
              textTheme: ThemeData.light().textTheme,
            ),
          ),
          home: TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
            child: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () {
                      showHomeNewTeamDialog(context, teamCubit);
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(TpDialogPageShell), findsOneWidget);
    expect(find.byType(TpDialogHeader), findsOneWidget);
    expect(find.byType(TpDialogMobileNavBar), findsNothing);
    expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    final shellRect = tester.getRect(find.byType(TpDialogPageShell));
    expect(shellRect.height, lessThan(700));
    expect(
      MediaQuery.sizeOf(tester.element(find.byType(TpDialogPageShell))).width,
      greaterThanOrEqualTo(WorkspacePanePolicy.narrowBreakpointWidth),
    );
  });
}
