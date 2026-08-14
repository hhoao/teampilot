import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/skills/skill_discovery_repos_panel.dart';
import 'package:teampilot/pages/skills/skill_discovery_section.dart';
import 'package:teampilot/pages/skills/skill_marketplace_panel.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _TmpSource implements SkillMarketplaceSource {
  @override
  String get id => 'tmp';
  @override
  String get label => 'Tmp Market';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();
  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async =>
      const MarketplaceSearchResult(skills: [], hasNext: false);

  @override
  Future<void> setApiKey(String key) async {}
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-disc-section-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Widget wrap(SkillCubit cubit) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: BlocProvider<SkillCubit>.value(
        value: cubit,
        child: SizedBox(
          height: 800,
          child: SkillDiscoverySection(onGoRepos: () {}),
        ),
      ),
    ),
  );

  testWidgets('renders a toggle per registered marketplace', (tester) async {
    final cubit = SkillCubit(
      SkillRepository(),
      marketplaces: [_TmpSource()],
    );
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('Tmp Market'), findsOneWidget);
    expect(find.text('Repos'), findsOneWidget);
  });

  testWidgets('tapping a marketplace toggle shows the shared panel', (
    tester,
  ) async {
    final cubit = SkillCubit(
      SkillRepository(),
      marketplaces: [_TmpSource()],
    );
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.byType(SkillMarketplacePanel), findsNothing);

    await tester.tap(find.text('Tmp Market'));
    await tester.pumpAndSettle();

    expect(find.byType(SkillMarketplacePanel), findsOneWidget);
    expect(find.byType(SkillDiscoveryReposBody), findsNothing);
  });
}
