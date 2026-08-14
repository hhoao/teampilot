import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/hooks/hook_editor_dialog.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late Filesystem fs;
  late HookRepository repository;
  late HookCubit cubit;

  setUp(() {
    fs = InMemoryFilesystem();
    repository = HookRepository(fs: fs, teampilotRoot: '/root');
    cubit = HookCubit(repository: repository);
  });

  tearDown(() => cubit.close());

  Future<void> pumpHost(
    WidgetTester tester, {
    HookDefinition? definition,
  }) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
          child: BlocProvider<HookCubit>.value(
            value: cubit,
            child: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showHookEditorDialog(
                    context,
                    cubit: cubit,
                    definition: definition,
                    repository: repository,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('save creates the hook and closes the dialog', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('hook-name')), 'On start');
    await tester.enterText(
      find.byKey(const Key('hook-command')),
      'echo start',
    );
    await tester.tap(find.byKey(const Key('hook-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-save')), findsNothing);
    final saved = await repository.loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'On start');
    expect(saved.single.id, 'on-start');
    expect((saved.single.action as CommandHookAction).command, 'echo start');
  });

  testWidgets('cancel closes the dialog without saving', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hook-name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hook-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-name')), findsNothing);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('close button exits the dialog (no dead end)', (tester) async {
    await pumpHost(tester);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-name')), findsNothing);
    expect(await repository.loadAll(), isEmpty);
  });

  testWidgets('edit pre-fills fields and loads script content', (tester) async {
    await repository.save(
      const HookDefinition(
        id: 'h1',
        name: 'Guard',
        description: 'Blocks rm',
        event: HookEvent.preToolUse,
        matcher: 'Bash',
        policy: HookPolicy.deny,
        action: CommandHookAction.script(fileName: 'hook.sh'),
      ),
    );
    await repository.writeScript('h1', 'hook.sh', 'exit 2');
    final definition = await repository.load('h1');

    await pumpHost(tester, definition: definition);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-name')))
          .controller!
          .text,
      'Guard',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-script')))
          .controller!
          .text,
      'exit 2',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-matcher')))
          .controller!
          .text,
      'Bash',
    );
  });
}
