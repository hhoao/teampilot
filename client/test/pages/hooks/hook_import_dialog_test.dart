import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/hooks/hook_import_dialog.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/hook/import/hook_import_service.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookCubit cubit;
  late HookImportParser parser;
  late HookImportService service;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    cubit = HookCubit(repository: repository);
    parser = HookImportParser(fs: fs, teampilotRoot: '/root');
    service = HookImportService(repository: repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpDialog(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      RepositoryProvider<HookRepository>.value(
        value: repository,
        child: RepositoryProvider<HookImportParser>.value(
          value: parser,
          child: RepositoryProvider<HookImportService>.value(
            value: service,
            child: BlocProvider<HookCubit>.value(
              value: cubit,
              child: MaterialApp(
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: TpTheme(
                  data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
                  child: Builder(
                    builder: (context) => Scaffold(
                      body: TextButton(
                        onPressed: () => showHookImportDialog(context),
                        child: const Text('import'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('paste json → parse → preview → import persists', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    // 默认 CLI 为 claude；粘贴 claude hooks 段
    await tester.enterText(
      find.byKey(const Key('hook-import-json')),
      '{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo done"}]}]}}',
    );
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(find.text('Stop'), findsOneWidget);
    expect(find.byKey(const Key('hook-import-preview')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hook-import-confirm')));
    await tester.pumpAndSettle();

    final all = await repository.loadAll();
    expect(all, hasLength(1));
    expect(all.single.event.name, 'stop');
    expect(find.byKey(const Key('hook-import-confirm')), findsNothing);
  });

  testWidgets('parse errors show message and keep dialog open', (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('hook-import-json')), 'nope');
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(find.text('Invalid hook JSON'), findsOneWidget);
    expect(find.byKey(const Key('hook-import-confirm')), findsNothing);
  });

  testWidgets('empty group parses to a no-hooks error, not silence',
      (tester) async {
    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('hook-import-json')),
      '{"hooks": {"Stop": []}}',
    );
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(find.text('No hooks found'), findsOneWidget);
    expect(find.byKey(const Key('hook-import-preview')), findsNothing);
  });

  testWidgets('draft matching an existing definition shows overwrite badge',
      (tester) async {
    // 预置一条与解析 draft 同 id 的定义（确定性 id，先解析拿 id）。
    const json = '{"hooks": {"Stop": ['
        '{"hooks": [{"type": "command", "command": "echo done"}]}]}}';
    final parsed = await parser.parseJson(cli: CliTool.claude, jsonText: json);
    final id = parsed.drafts.single.definition.id;
    await repository.save(
      HookDefinition(
        id: id,
        name: 'existing',
        event: HookEvent.stop,
        action: const CommandHookAction.raw('echo done'),
      ),
    );

    await pumpDialog(tester);

    await tester.tap(find.text('import'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('hook-import-json')), json);
    await tester.tap(find.byKey(const Key('hook-import-parse')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(Key('hook-import-overwrite-$id')),
      findsOneWidget,
    );
    expect(find.text('Will overwrite'), findsOneWidget);
  });
}
