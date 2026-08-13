import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/hooks/hook_editor_page.dart';
import 'package:teampilot/services/hook/hook_repository.dart';
import 'package:teampilot/services/io/filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  Future<(Filesystem, HookCubit)> pumpEditor(
    WidgetTester tester, {
    HookDefinition? definition,
    HookRepository? repository,
  }) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final fs = InMemoryFilesystem();
    final repo = repository ?? HookRepository(fs: fs, teampilotRoot: '/root');
    final cubit = HookCubit(repository: repo);
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider(
          create: (_) => LayoutCubit(),
          child: Scaffold(
            body: HookEditorPage(
              cubit: cubit,
              definition: definition,
              repository: repo,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (fs, cubit);
  }

  testWidgets('editor renders fields and saves a raw command hook', (
    tester,
  ) async {
    final (fs, _) = await pumpEditor(tester);

    expect(find.text('On session start'), findsNothing);
    expect(
      find.byKey(const Key('hook-capability-matrix')),
      findsOneWidget,
    );
    expect(find.text('✓'), findsNWidgets(4));
    expect(find.text('≈'), findsOneWidget);
    expect(find.text('✗'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('hook-name')),
      'On session start',
    );
    await tester.enterText(
      find.byKey(const Key('hook-command')),
      'echo start',
    );
    await tester.enterText(
      find.byKey(const Key('hook-matcher')),
      'rm -rf',
    );
    await tester.tap(find.byKey(const Key('hook-save')));
    await tester.pumpAndSettle();

    final saved = await HookRepository(
      fs: fs,
      teampilotRoot: '/root',
    ).loadAll();
    expect(saved, hasLength(1));
    expect(saved.single.name, 'On session start');
    expect(saved.single.matcher, 'rm -rf');
  });

  testWidgets('edit mode pre-fills fields and loads script content', (
    tester,
  ) async {
    final fs = InMemoryFilesystem();
    final repository = HookRepository(fs: fs, teampilotRoot: '/root');
    const definition = HookDefinition(
      id: 'my-hook',
      name: 'Existing',
      event: HookEvent.stop,
      action: CommandHookAction.script(fileName: 'hook.sh'),
      env: {'FOO': 'bar'},
    );
    await repository.save(definition);
    await repository.writeScript('my-hook', 'hook.sh', 'echo existing');
    await pumpEditor(tester, definition: definition, repository: repository);

    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-name')))
          .controller!
          .text,
      'Existing',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-script')))
          .controller!
          .text,
      'echo existing',
    );
    expect(find.byKey(const Key('hook-policy')), findsNothing);

    await tester.tap(find.byKey(const Key('hook-save')));
    await tester.pumpAndSettle();
    expect(
      await repository.readScript('my-hook', 'hook.sh'),
      'echo existing',
    );
  });
}
