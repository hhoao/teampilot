import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CliPresetsRepository repo;
  late CliPresetsCubit cubit;
  late AppProviderCubit appProviderCubit;

  Future<void> seedPreset() async {
    final preset = CliPreset(
      id: 'preset-1',
      name: 'Old Name',
      cli: CliTool.claude,
      provider: 'anthropic',
      model: 'claude-sonnet-4-5',
      effort: 'high',
      createdAt: 1,
      updatedAt: 1,
    );
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([preset.toJson()]),
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CliPresetsRepository(fs: fs, presetsPath: '/cli-presets.json');
    cubit = CliPresetsCubit(repository: repo);
    appProviderCubit = AppProviderCubit(basePath: '/tmp');
  });

  tearDown(() {
    cubit.close();
    appProviderCubit.close();
  });

  Future<void> pumpManageDialog(WidgetTester tester) async {
    await seedPreset();
    await cubit.load();
    await tester.pumpWidget(
      CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: appProviderCubit),
            BlocProvider.value(value: cubit),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: CliPresetsManageDialog()),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('edit preset name persists and updates manage list', (
    tester,
  ) async {
    await pumpManageDialog(tester);

    expect(find.text('Old Name'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'New Name');
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    )!;
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);

    expect(find.text('New Name'), findsOneWidget);
    expect(find.text('Old Name'), findsNothing);
    expect(cubit.state.presets.single.name, 'New Name');

    final reloaded = await CliPresetsRepository(
      fs: fs,
      presetsPath: '/cli-presets.json',
    ).load();
    expect(reloaded.single.name, 'New Name');
  });
}