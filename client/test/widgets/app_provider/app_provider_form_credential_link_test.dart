import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/managed_provider_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_repository.dart';
import 'package:teampilot/repositories/managed_provider_usage_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/widgets/app_provider/app_provider_form_sheet.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ManagedProviderCubit managedCubit;

  setUp(() {
    fs = InMemoryFilesystem();
    final usageRepository = ManagedProviderUsageRepository(
      fs: fs,
      cachePath: '/tp/usage-cache.json',
    );
    final managedRepository = ManagedProviderRepository(
      fs: fs,
      configPath: '/tp/managed-providers.json',
      onProvidersDeleted: usageRepository.deleteMany,
    );
    managedCubit = ManagedProviderCubit(repository: managedRepository);
  });

  tearDown(() async {
    await managedCubit.close();
  });

  ManagedProvider _secretEntry() => ManagedProvider(
    id: 'm1',
    name: 'Entry m1',
    kind: ManagedProviderKind.apiBalance,
    adapterId: 'http-json',
    credentialRef: 'managed-provider:m1',
  );

  Widget wrapForm(Widget form) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => AppProviderCubit()),
            BlocProvider.value(value: managedCubit),
          ],
          child: Scaffold(body: SizedBox(width: 1000, height: 1400, child: form)),
        ),
      ),
    );
  }

  testWidgets('linking a managed entry hides the apiKey input and drafts the link',
      (tester) async {
    // Seed the catalog synchronously — an async upsert before pumpWidget
    // leaves the real event loop busy and pumpAndSettle never settles.
    managedCubit.emit(
      ManagedProviderState(
        status: ManagedProviderLoadStatus.ready,
        providers: [_secretEntry()],
      ),
    );

    AppProviderConfig? saved;
    await tester.pumpWidget(
      wrapForm(
        AppProviderFormPage(
          cli: CliTool.claude,
          onCancel: () {},
          onSaved: (provider) => saved = provider,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The credential-link picker needs an apiKey-class category. Pick the
    // DeepSeek preset (cn-official) so the apiKey block renders.
    await tester.tap(find.byKey(const ValueKey('app-provider-preset-claude')));
    await tester.pumpAndSettle();
    // The preset list is long; narrow it via the overlay's search field.
    await tester.enterText(find.byType(TextField).first, 'DeepSeek');
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    // Select the credential link mode and the managed entry.
    await tester.scrollUntilVisible(
      find.byKey(const Key('app-provider-credential-link')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('app-provider-credential-link')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entry m1').last);
    await tester.pumpAndSettle();

    // Own-key input is hidden while linked; the chip names the entry.
    expect(
      find.byKey(const Key('app-provider-credential-link-chip')),
      findsOneWidget,
    );
    final l10n = tester.element(find.byType(Scaffold)).l10n;
    expect(find.text(l10n.appProviderCredentialLinkedTo('Entry m1')), findsOneWidget);

    // The save button emits a draft whose credentialLink is set and whose
    // apiKey stays empty.
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.credentialLink, 'm1');
    expect(saved!.apiKey, isEmpty);
  });
}
