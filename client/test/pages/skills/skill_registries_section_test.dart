import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/pages/skills/skill_registries_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/registry/api_registry_source.dart';
import 'package:teampilot/services/skill/registry/git_repo_registry_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

List<SkillRegistrySource> _rebuild(SkillRegistriesConfig c) => [
  for (final cfg in c.sources)
    if (cfg.kind == SkillRegistryKind.api)
      ApiRegistrySource(cfg)
    else
      GitRepoRegistrySource(
        cfg,
        discoverableProvider: () async => const [],
        syncNow: () async {},
      ),
];

/// Lets pending real-async work (disk IO) spawned from FakeAsync UI callbacks
/// make progress: real event loop turns flush IO completions, pumps drain the
/// FakeAsync continuation queue.
Future<void> _flushRealIo(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 80)),
    );
    await tester.pumpAndSettle();
  }
}

Future<String?> _readRegistriesJson(WidgetTester tester, String basePath) {
  return tester.runAsync<String?>(
    () => AppStorage.fs.readString(
      AppPaths.skillRegistriesConfigPathForTeampilotRoot(basePath),
    ),
  );
}

Future<String?> _waitForRegistriesJson(
  WidgetTester tester,
  String basePath,
  bool Function(String raw) predicate,
) async {
  String? raw;
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    raw = await _readRegistriesJson(tester, basePath);
    if (raw != null && predicate(raw)) return raw;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  return raw;
}

void main() {
  late Directory tmp;
  late AppPaths paths;
  late SkillRegistryConfigService cfgService;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('skill-reg-section-');
    paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
    cfgService = SkillRegistryConfigService(teampilotRoot: paths.basePath);
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(SkillCubit cubit) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        ThemeData.light().colorScheme,
        scale: 1.0,
      ),
      child: Scaffold(
        body: BlocProvider<SkillCubit>.value(
          value: cubit,
          child: const SizedBox(height: 900, child: SkillRegistriesSection()),
        ),
      ),
    ),
  );

  Future<SkillCubit> buildCubit(WidgetTester tester) async {
    final cubit = await tester.runAsync<SkillCubit>(() async {
      final path = AppPaths.skillRegistriesConfigPathForTeampilotRoot(
        paths.basePath,
      );
      final stat = await AppStorage.fs.stat(path);
      if (!stat.isFile) {
        await cfgService.save(SkillRegistriesConfig.defaults());
      }
      final c = SkillCubit(
        SkillRepository(),
        registryConfigService: cfgService,
        initialSources: const [],
        rebuildSources: _rebuild,
      );
      await c.loadAll();
      return c;
    });
    return cubit!;
  }

  testWidgets('shows source rows with labels and switches', (tester) async {
    final cubit = await buildCubit(tester);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('https://skills.sh'), findsOneWidget);
    expect(find.text('https://skillsmp.com/api/v1'), findsOneWidget);
    expect(find.text('@SkillsMP'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(6)); // 2 API + 4 default git
  });

  testWidgets('edit dialog saves display name to registries.json', (tester) async {
    final cubit = await buildCubit(tester);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://skills.sh'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'My Skills');
    await tester.tap(find.text('Save'));
    final raw = await _waitForRegistriesJson(
      tester,
      paths.basePath,
      (value) => value.contains('My Skills'),
    );
    expect(raw, contains('My Skills'));
  });

  testWidgets('add API source flow', (tester) async {
    final cubit = await buildCubit(tester);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add registry source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('API source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SkillsMP compatible'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'My API');
    await tester.tap(find.text('Save'));
    await _flushRealIo(tester);
    expect(find.text('@My API'), findsWidgets);
  });

  testWidgets('clearing token in edit dialog shows unauthenticated badge', (
    tester,
  ) async {
    final defaults = SkillRegistriesConfig.defaults();
    final withToken = SkillRegistriesConfig(sources: [
      for (final s in defaults.sources)
        s.id == 'skillsMp' ? s.copyWith(apiToken: 'tok123') : s,
    ]);
    await tester.runAsync(() => cfgService.save(withToken));
    final cubit = await buildCubit(tester);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('Authenticated'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsWidgets);
    await tester.tap(find.text('https://skillsmp.com/api/v1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), '');
    await tester.tap(find.text('Save'));

    // The edit dialog persists real-async (disk IO + registry reload), so
    // poll for the badge transition instead of relying on a fixed flush.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (find.text('Authenticated').evaluate().isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      for (var i = 0; i < 2 && find.text('Authenticated').evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)),
        );
        await tester.pumpAndSettle();
      }
    }
    expect(DateTime.now().isBefore(deadline), isTrue,
        reason: 'badge should drop Authenticated after clearing the token');
    expect(find.text('Authenticated'), findsNothing);
    expect(find.text('Unauthenticated'), findsOneWidget);
    expect(find.text('@SkillsMP'), findsOneWidget);
  });

  testWidgets('remove custom git source confirms and deletes', (tester) async {
    final defaults = SkillRegistriesConfig.defaults();
    final custom = SkillRegistrySourceConfig(
      id: 'git-vercel-ai',
      kind: SkillRegistryKind.gitRepo,
      label: 'vercel/ai',
      gitOwner: 'vercel',
      gitName: 'ai',
      gitBranch: 'main',
    );
    await tester.runAsync(() => cfgService.save(
      SkillRegistriesConfig(sources: [...defaults.sources, custom]),
    ));
    final cubit = await buildCubit(tester);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://github.com/vercel/ai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await _flushRealIo(tester);
    await tester.tap(find.byIcon(Icons.delete_outline).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await _flushRealIo(tester);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline) &&
        find.text('https://github.com/vercel/ai').evaluate().isNotEmpty) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.text('https://github.com/vercel/ai'), findsNothing);
  });
}