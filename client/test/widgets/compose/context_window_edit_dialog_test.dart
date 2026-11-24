import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';
import 'package:teampilot/widgets/compose/context_window_edit_dialog.dart';

import '../../support/in_memory_filesystem.dart';

Future<void> _openDialog(
  WidgetTester tester, {
  required int? current,
  required void Function(int? result) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizationsCompatDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: appLocalizationsSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showContextWindowEditDialog(
                context,
                modelName: 'my-model',
                currentTokens: current,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('save returns the positive token count', (tester) async {
    int? result;
    await _openDialog(tester, current: null, onResult: (v) => result = v);

    await tester.enterText(find.byType(TextField), '200000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 200000);
  });

  testWidgets('empty input clears the window', (tester) async {
    int? result;
    await _openDialog(tester, current: 128000, onResult: (v) => result = v);

    expect(find.text('128000'), findsOneWidget); // seeded controller
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(result, 0);
  });

  testWidgets('use model default returns clear', (tester) async {
    int? result;
    await _openDialog(tester, current: 128000, onResult: (v) => result = v);

    await tester.tap(find.text('Use model default'));
    await tester.pumpAndSettle();

    expect(result, 0);
  });

  testWidgets('cancel returns null', (tester) async {
    var called = false;
    int? result = -1;
    await _openDialog(
      tester,
      current: 128000,
      onResult: (v) {
        called = true;
        result = v;
      },
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
  });

  testWidgets('selector pick persists and clears the window', (tester) async {
    final cubit = AppProviderCubit(storage: fakeHomeStorage());
    addTearDown(cubit.close);
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'q1',
        cli: CliTool.qoder,
        name: 'Qoder',
        defaultModel: 'm1',
      ),
    );

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    await applyComposeContextWindowPick(
      ctx,
      request: const CascadeContextWindowPick(
        cli: CliTool.qoder,
        providerId: 'q1',
        modelId: 'm1',
        tokens: 200000,
      ),
    );
    expect(
      resolveModelContextWindow(
        cubit.state.providersFor(CliTool.qoder).single,
        model: 'm1',
        entryId: 'm1',
      ),
      200000,
    );

    await applyComposeContextWindowPick(
      ctx,
      request: const CascadeContextWindowPick(
        cli: CliTool.qoder,
        providerId: 'q1',
        modelId: 'm1',
        tokens: null,
      ),
    );
    expect(
      resolveModelContextWindow(
        cubit.state.providersFor(CliTool.qoder).single,
        model: 'm1',
        entryId: 'm1',
      ),
      isNull,
    );
  });

  testWidgets('editor persists the window on the provider row', (tester) async {
    final cubit = AppProviderCubit(storage: fakeHomeStorage());
    addTearDown(cubit.close);
    await cubit.upsertProvider(
      const AppProviderConfig(
        id: 'q1',
        cli: CliTool.qoder,
        name: 'Qoder',
        defaultModel: 'm1',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizationsCompatDelegate(),
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: appLocalizationsSupportedLocales,
        home: BlocProvider.value(
          value: cubit,
          child: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showComposeContextWindowEditor(
                  context,
                  request: const CascadeContextWindowEditRequest(
                    cli: CliTool.qoder,
                    providerId: 'q1',
                    modelId: 'm1',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '200000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = cubit.state.providersFor(CliTool.qoder).single;
    expect(
      resolveModelContextWindow(saved, model: 'm1', entryId: 'm1'),
      200000,
    );
  });
}
