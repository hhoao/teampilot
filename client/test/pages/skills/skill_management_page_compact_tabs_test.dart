import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/skills/skill_management_page.dart';
import 'package:teampilot/pages/skills/skill_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';
import 'package:teampilot/widgets/settings/workspace_section_tab_bar.dart';

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

  testWidgets('narrow embedded shows compact section tabs', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: theme,
          home: Scaffold(
            body: BlocProvider<SkillCubit>.value(
              value: cubit,
              child: const SizedBox(
                width: 400,
                height: 800,
                child: SkillManagementPage(
                  section: SkillSection.installed,
                  embedded: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Discovery'), findsOneWidget);
    expect(find.text('Repos'), findsOneWidget);
    expect(find.byType(WorkspaceSectionTabBar), findsOneWidget);
    expect(find.byType(WorkspaceSplitShell), findsNothing);
  });
}
