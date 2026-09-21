import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/skills/skill_installed_section.dart';
import 'package:teampilot/services/storage/app_paths.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

void main() {
  late SkillCubit cubit;

  const skill = Skill(
    id: 'local:demo',
    name: 'demo-skill',
    description: 'short',
    directory: 'demo',
    installedAt: 1,
    updatedAt: 1,
  );

  setUp(() {
    setUpTestAppStorage();
    // Widget tests run under FakeAsync; LocalFilesystem dart:io reads hang
    // SkillDetailView's loading spinner. Keep testHomeStorage.fs.
    final paths = testHomeStorage.paths;
    final home = testHomeStorage.home;
    installTestHomeStorage(
      filesystem: InMemoryFilesystem(pathContext: testHomeStorage.fs.pathContext),
      paths: paths,
      home: home,
      cwd: home,
    );
    cubit = testSkillCubit();
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    tearDownTestAppStorage();
  });

  Widget host(SkillState state) {
    final theme = ThemeData(useMaterial3: true);
    return TpTheme(
      data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: theme,
        home: Scaffold(
          body: BlocProvider<SkillCubit>.value(
            value: cubit,
            child: SizedBox(
              width: 720,
              height: 640,
              child: SkillInstalledSection(
                state: state,
                onGoDiscovery: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('view opens detail and back returns to the list', (tester) async {
    final fs = testHomeStorage.fs;
    final dir = AppPaths.skillsDirForTeampilotRoot(
      testHomeStorage.paths.basePath,
    );
    await fs.writeString(
      fs.pathContext.join(dir, 'demo', 'SKILL.md'),
      '# Hello skill\n\nDo the thing.',
    );

    await tester.pumpWidget(host(const SkillState(installed: [skill])));
    await tester.pumpAndSettle();

    expect(find.text('demo-skill'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    expect(find.textContaining('Do the thing.'), findsWidgets);
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('missing SKILL.md shows empty copy', (tester) async {
    await tester.pumpWidget(host(const SkillState(installed: [skill])));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(
      find.text('No SKILL.md found for this skill.'),
      findsOneWidget,
    );
  });

  testWidgets('detail closes when the skill leaves installed', (tester) async {
    await tester.pumpWidget(host(const SkillState(installed: [skill])));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    await tester.pumpWidget(host(const SkillState()));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
  });
}
