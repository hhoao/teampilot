import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/skills/skill_marketplace_panel.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _NoFilterSource implements SkillMarketplaceSource {
  @override
  String get id => 'noFilters';
  @override
  String get label => 'noFilters';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  final queries = <MarketplaceSearchQuery>[];

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    queries.add(query);
    return const MarketplaceSearchResult(skills: [], hasNext: false);
  }

  @override
  Future<void> setApiKey(String key) async {}
}

class _FilteredSource implements SkillMarketplaceSource {
  @override
  String get id => 'filtered';
  @override
  String get label => 'filtered';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities(
    supportsSortBy: true,
    supportsLanguage: true,
    supportsCategory: true,
    categoryChoices: {'data-ai': 'Data & AI'},
    languageChoices: ['zh', 'en'],
  );

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async =>
      const MarketplaceSearchResult(skills: [], hasNext: false);

  @override
  Future<void> setApiKey(String key) async {}
}

class _ThrowingSource implements SkillMarketplaceSource {
  _ThrowingSource(this.error);

  final Object error;

  @override
  String get id => 'throwing';
  @override
  String get label => 'throwing';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    throw error;
  }

  @override
  Future<void> setApiKey(String key) async {}
}

class _SingleResultSource implements SkillMarketplaceSource {
  _SingleResultSource(this.skill);

  final MarketplaceSkill skill;

  @override
  String get id => 'single';
  @override
  String get label => 'single';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async =>
      MarketplaceSearchResult(skills: [skill], hasNext: false);

  @override
  Future<void> setApiKey(String key) async {}
}

class _TestSkillCubit extends SkillCubit {
  _TestSkillCubit(super.repo, {super.marketplaces});

  void setInstalled(List<Skill> installed) =>
      emit(state.copyWith(installed: installed));
}

Widget wrap(Widget child, SkillCubit cubit) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: BlocProvider<SkillCubit>.value(value: cubit, child: child),
  ),
);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-mp-panel-');
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

  SkillCubit cubit([List<SkillMarketplaceSource> sources = const []]) =>
      SkillCubit(SkillRepository(), marketplaces: sources);

  testWidgets('renders search bar; no filters when capabilities empty', (
    tester,
  ) async {
    final source = _NoFilterSource();
    final c = cubit([source]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sort'), findsNothing);
  });

  testWidgets('search submits to source', (tester) async {
    final source = _NoFilterSource();
    final c = cubit([source]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.enterText(find.byType(TextField), 'seo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(source.queries, isNotEmpty);
    expect(source.queries.single.query, 'seo');
  });

  testWidgets('renders filter dropdowns when capabilities declare them', (
    tester,
  ) async {
    final source = _FilteredSource();
    final c = cubit([source]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });

  testWidgets('generic search failure shows localized error label', (
    tester,
  ) async {
    final source = _ThrowingSource(MarketplaceFetchException('boom'));
    final c = cubit([source]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.enterText(find.byType(TextField), 'seo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('Search failed'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('quota failure keeps quota hint text', (tester) async {
    final source = _ThrowingSource(MarketplaceQuotaException('quota boom'));
    final c = cubit([source]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.enterText(find.byType(TextField), 'seo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.textContaining('anonymous quota'), findsOneWidget);
    expect(find.textContaining('Search failed'), findsNothing);
  });

  testWidgets('shows Installed badge when basename matches installed skill', (
    tester,
  ) async {
    final skill = MarketplaceSkill(
      key: 'acme/skills-foo/skills/foo',
      name: 'Foo Skill',
      description: 'A foo skill.',
      repoOwner: 'acme',
      repoName: 'skills-foo',
      directory: 'skills/foo',
      githubUrl: 'https://github.com/acme/skills-foo',
    );
    final source = _SingleResultSource(skill);
    final c = _TestSkillCubit(SkillRepository(), marketplaces: [source]);
    c.setInstalled([
      Skill(
        id: 'foo',
        name: 'Foo Skill',
        description: 'A foo skill.',
        directory: 'foo',
        repoOwner: 'acme',
        repoName: 'skills-foo',
        installedAt: 1,
        updatedAt: 1,
      ),
    ]);
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.enterText(find.byType(TextField), 'seo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Installed'), findsOneWidget);
  });
}
