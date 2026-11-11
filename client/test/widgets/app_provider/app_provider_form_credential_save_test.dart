import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/widgets/app_provider/app_provider_form_sheet.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  testWidgets(
    'save after a form-side credential action keeps the created row id',
    (tester) async {
      final storage = fakeHomeStorage();
      final repository = AppProviderRepository(
        basePath: '/tp',
        storage: storage,
      );
      final cubit = AppProviderCubit(
        repository: repository,
        basePath: '/tp',
        storage: storage,
      );
      await cubit.load();

      AppProviderConfig? saved;

      await tester.pumpWidget(
        RepositoryProvider<HomeStorage>.value(
          value: storage,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizationsCompatDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: appLocalizationsSupportedLocales,
            home: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: BlocProvider.value(
                value: cubit,
                child: Scaffold(
                  body: SizedBox(
                    width: 1000,
                    height: 1400,
                    child: AppProviderFormPage(
                      cli: CliTool.codex,
                      onCancel: () {},
                      onSaved: (draft) => saved = draft,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Pick the official preset so the credential action bar is shown.
      await tester.tap(
        find.byKey(const ValueKey('app-provider-preset-codex')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OpenAI Official').last);
      await tester.pumpAndSettle();

      // A credential action persists the draft row before credential IO.
      await tester.tap(find.text('Import from ~/.codex'));
      // The action also shows a toast; advance past its 5s auto-close timer
      // so no timer is left pending when the test tears down.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      final rows = cubit.state.providersFor(CliTool.codex);
      expect(rows, hasLength(1));
      final createdId = rows.single.id;

      // Editing the display name must not turn save into a second row.
      await tester.enterText(find.byType(TpInput).first, 'My Work Account');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.id, createdId);
    },
  );
}
