import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/cli_presets_manage_dialog.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CliPresetsRepository repo;
  late CliPresetsCubit cubit;
  late AppProviderCubit appProviderCubit;

  Future<void> seedPreset({
    String name = 'Old Name',
    String provider = 'anthropic',
    String model = 'claude-sonnet-4-5',
  }) async {
    final preset = CliPreset(
      id: 'preset-1',
      name: name,
      cli: CliTool.claude,
      provider: provider,
      model: model,
      effort: 'high',
      createdAt: 1,
      updatedAt: 1,
    );
    await fs.writeString('/cli-presets.json', jsonEncode([preset.toJson()]));
  }

  Future<void> seedProviderCatalog() async {
    await fs.writeString(
      '/tmp/providers/claude/providers.json',
      jsonEncode({
        'providers': {
          'anthropic': {
            'id': 'anthropic',
            'cli': 'claude',
            'name': 'Anthropic',
            'category': 'official',
            'isOfficial': true,
            'defaultModel': 'claude-sonnet-4-5',
          },
        },
      }),
    );
  }

  setUp(() {
    fs = InMemoryFilesystem();
    repo = CliPresetsRepository(fs: fs, presetsPath: '/cli-presets.json');
    cubit = CliPresetsCubit(repository: repo);
    appProviderCubit = AppProviderCubit(
      repository: AppProviderRepository(basePath: '/tmp', fs: fs),
    );
  });

  tearDown(() {
    cubit.close();
    appProviderCubit.close();
  });

  Future<void> pumpManageDialog(
    WidgetTester tester, {
    String presetName = 'Old Name',
    String presetProvider = 'anthropic',
  }) async {
    await seedPreset(name: presetName, provider: presetProvider);
    await seedProviderCatalog();
    await cubit.load();
    await appProviderCubit.load(reconcileCredentials: false);
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

  Finder modelSelectFinder() {
    return find.byWidgetPredicate((w) => w is TpSelectWithCustomInput);
  }

  testWidgets('edit preset name persists and updates manage list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    expect(find.text('Old Name'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'New Name');
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
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

  testWidgets('edit preset model persists and shows on reopen', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    expect(find.text('Old Name'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final modelSelect = modelSelectFinder();
    expect(modelSelect, findsOneWidget);

    final select = find.descendant(
      of: modelSelect,
      matching: find.byType(TpSelect<String>),
    );
    expect(select, findsOneWidget);
    final before = tester.widget<TpSelect<String>>(select).items.toList();
    expect(before, isNotEmpty);

    final target = before.firstWhere((m) => m != 'claude-sonnet-4-5');
    await tester.tap(select);
    await tester.pumpAndSettle();
    await tester.tap(find.text(target).last);
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(cubit.state.presets.single.model, target);

    final reloaded = await CliPresetsRepository(
      fs: fs,
      presetsPath: '/cli-presets.json',
    ).load();
    expect(reloaded.single.model, target);

    // Reopen the edit dialog: the picker must show the persisted model.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final reopened = tester
        .widget<TpSelectWithCustomInput>(modelSelectFinder())
        .value;
    expect(reopened, target);
  });

  testWidgets('save stays reachable on short windows (no overflow)', (
    tester,
  ) async {
    // Regression: the edit dialog previously overflowed on short windows,
    // pushing the action bar off-screen so clicking save did nothing.
    tester.view.physicalSize = const Size(1280, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpManageDialog(tester);
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    final saveButton = find.widgetWithText(FilledButton, l10n.save);
    expect(saveButton, findsOneWidget);

    final saveBox = tester.getRect(saveButton);
    expect(saveBox.bottom, lessThan(600), reason: 'save must be on-screen');

    await tester.enterText(find.byType(TextField).first, 'Short Window Name');
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(cubit.state.presets.single.name, 'Short Window Name');
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving with empty name shows inline error and keeps dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(tester);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(l10n.formFieldRequired), findsOneWidget);
    expect(cubit.state.presets.single.name, 'Old Name');

    await tester.enterText(find.byType(TextField), 'Fixed Name');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(cubit.state.presets.single.name, 'Fixed Name');
  });

  testWidgets('saving without provider shows inline error and keeps dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpManageDialog(
      tester,
      presetName: 'No Provider',
      presetProvider: '',
    );

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    await tester.enterText(find.byType(TextField), 'Named Preset');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, l10n.save));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    // The closed trigger's hint shares the string; the inline error adds one.
    expect(find.text(l10n.selectProvider), findsExactly(2));
    expect(
      cubit.state.presets.map((p) => p.name),
      isNot(contains('Named Preset')),
    );
  });

  testWidgets('manage list ellipsizes long preset name and reveals full text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longName = 'deepseek-v4-pro[1m]-very-long-preset-name-overflow';
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([
        CliPreset(
          id: 'preset-long',
          name: longName,
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'claude-sonnet-4-5',
          createdAt: 1,
          updatedAt: 1,
        ).toJson(),
      ]),
    );
    await seedProviderCatalog();
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

    expect(find.text(longName), findsOneWidget);
    final tooltip = find.byType(Tooltip);
    expect(tooltip, findsWidgets);
    final messages = tester
        .widgetList<Tooltip>(tooltip)
        .map((t) => t.message)
        .toList();
    expect(messages, contains(longName));
    expect(messages, anyElement(contains('claude-sonnet-4-5')));
  });

  testWidgets('edit dialog model dropdown ellipsizes a long model id with '
      'full-text Tooltip', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const longModel = 'deepseek-v4-pro[1m]-a-very-long-model-id-overflow';
    await fs.writeString(
      '/cli-presets.json',
      jsonEncode([
        CliPreset(
          id: 'preset-long-model',
          name: 'long-model preset',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: longModel,
          createdAt: 1,
          updatedAt: 1,
        ).toJson(),
      ]),
    );
    await seedProviderCatalog();
    await cubit.load();
    await appProviderCubit.load(reconcileCredentials: false);
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

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final picker = modelSelectFinder();
    expect(picker, findsOneWidget);
    final tooltips = tester.widgetList<Tooltip>(find.byType(Tooltip));
    expect(
      tooltips.map((t) => t.message).toList(),
      anyElement(contains(longModel)),
    );
  });
}
