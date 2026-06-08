import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/ai_features_config_section.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(tearDownTestAppStorage);

  testWidgets('renders a card per AI feature', (tester) async {
    late Directory temp;
    late AiFeatureSettingsCubit cubit;
    late AppProviderCubit appProviderCubit;
    late SessionPreferencesCubit sessionPreferencesCubit;

    await tester.runAsync(() async {
      temp = await Directory.systemTemp.createTemp('ai_features_cfg_');
      final prefs = await SharedPreferences.getInstance();
      cubit = AiFeatureSettingsCubit(
        repository: InMemoryAppSettingsRepository(),
      );
      appProviderCubit = AppProviderCubit(basePath: temp.path);
      sessionPreferencesCubit = SessionPreferencesCubit(
        repository: SessionPreferencesRepository(prefs),
      );
      await sessionPreferencesCubit.load();
    });

    addTearDown(() async {
      await cubit.close();
      await appProviderCubit.close();
      await sessionPreferencesCubit.close();
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CliToolRegistryScope(
          registry: CliToolRegistry.builtIn(),
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: cubit),
              BlocProvider.value(value: appProviderCubit),
              BlocProvider.value(value: sessionPreferencesCubit),
            ],
            child: const Scaffold(
              body: AiFeaturesConfigWorkspace(showHeading: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Commit message generation'), findsOneWidget);
    expect(find.text('Team configuration generation'), findsOneWidget);
    expect(find.text('Configure'), findsNWidgets(2));
    expect(find.text('Not configured'), findsNWidgets(2));
  });
}
