import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/cli/cli_preset_dropdown_field.dart';

import '../../support/in_memory_filesystem.dart';

void _noop(String? _) {}

CliPresetsCubit _cubit() {
  final cubit = CliPresetsCubit(
    repository: CliPresetsRepository(
      fs: InMemoryFilesystem(),
      presetsPath: '/cli-presets.json',
    ),
  );
  cubit.emit(
    CliPresetsState(
      status: CliPresetsLoadStatus.ready,
      presets: [
        CliPreset(
          id: 'p-claude',
          name: 'Claude preset',
          cli: CliTool.claude,
          provider: 'anthropic',
          model: 'sonnet',
          createdAt: 1,
          updatedAt: 1,
        ),
        CliPreset(
          id: 'p-codex',
          name: 'Codex preset',
          cli: CliTool.codex,
          provider: 'openai',
          model: 'o3',
          createdAt: 1,
          updatedAt: 1,
        ),
      ],
    ),
  );
  return cubit;
}

Widget _host(CliPresetsCubit cubit, Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: BlocProvider<CliPresetsCubit>.value(
          value: cubit,
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: child,
          ),
        ),
      ),
    );

void main() {
  testWidgets('without filter all presets are offered', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TpSelect<String>>(find.byType(TpSelect<String>)).items,
      ['p-claude', 'p-codex'],
    );
  });

  testWidgets('cliFilter restricts items to that CLI', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          cliFilter: CliTool.codex,
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<TpSelect<String>>(find.byType(TpSelect<String>)).items,
      ['p-codex'],
    );
  });

  testWidgets('emptyHint is shown when filter matches nothing', (tester) async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _host(
        cubit,
        const CliPresetDropdownField(
          selectedPresetId: 'p-claude',
          cliFilter: CliTool.gemini,
          emptyHint: 'No presets available for this CLI.',
          onChanged: _noop,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No presets available for this CLI.'), findsOneWidget);
    expect(find.byType(TpSelect<String>), findsNothing);
  });
}
