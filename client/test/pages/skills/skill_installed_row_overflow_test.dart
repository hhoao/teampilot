import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/skills/skill_installed_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  late SkillCubit cubit;

  setUp(() {
    setUpTestAppStorage();
    cubit = SkillCubit(SkillRepository());
  });

  tearDown(() async {
    if (!cubit.isClosed) await cubit.close();
    tearDownTestAppStorage();
  });

  testWidgets('installed skill row does not overflow at phone width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const skill = Skill(
      id: 'git:owner/very-long-repo-name',
      name: 'very-long-skill-display-name',
      description: 'A skill with a long title and source label',
      directory: 'very-long-skill-display-name',
      repoOwner: 'very-long-org-name',
      repoName: 'very-long-repo-name-that-overflows',
      enabled: true,
      installedAt: 1,
      updatedAt: 1,
    );

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: Scaffold(
            body: BlocProvider<SkillCubit>.value(
              value: cubit,
                child: const SizedBox(
                width: 320,
                child: SkillInstalledRow(
                  skill: skill,
                  updateInfo: SkillUpdateInfo(
                    id: 'git:owner/very-long-repo-name',
                    name: 'very-long-skill-display-name',
                    remoteHash: 'abc',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('very-long-skill-display-name'), findsOneWidget);
  });
}
