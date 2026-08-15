import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/hook_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/hook_definition.dart';
import 'package:teampilot/models/hook_entry.dart';
import 'package:teampilot/models/hook_event.dart';
import 'package:teampilot/pages/hooks/hook_management_page.dart';
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

  Future<void> pumpListPage(WidgetTester tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => TpTheme(
                data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
                child: RepositoryProvider<HookRepository>.value(
                  value: repository,
                  child: MultiBlocProvider(
                    providers: [
                      BlocProvider<HookCubit>.value(value: cubit),
                      BlocProvider(create: (_) => LayoutCubit()),
                    ],
                    child: const Scaffold(body: HookManagementPage()),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('New hook opens the editor dialog and cancel exits', (
    tester,
  ) async {
    await pumpListPage(tester);

    await tester.tap(find.text('New hook'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-name')), findsOneWidget);

    await tester.tap(find.byKey(const Key('hook-cancel')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-name')), findsNothing);
  });

  testWidgets('card tap opens editor for the existing hook', (tester) async {
    await repository.save(
      const HookDefinition(
        id: 'existing',
        name: 'Existing',
        event: HookEvent.stop,
        action: CommandHookAction.raw('echo done'),
      ),
    );
    await cubit.load();
    await pumpListPage(tester);

    await tester.tap(find.text('Existing'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hook-name')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('hook-command')))
          .controller!
          .text,
      'echo done',
    );
  });
}
