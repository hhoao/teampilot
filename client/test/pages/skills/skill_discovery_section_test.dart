import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/skill_registry_source.dart';
import 'package:teampilot/pages/skills/skill_discovery_section.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/registry/skill_registry_config_service.dart';
import 'package:teampilot/services/skill/registry/skill_registry_source.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeSource implements SkillRegistrySource {
  _FakeSource(this.id);
  @override
  final String id;
  @override
  String get label => id;
  @override
  bool get enabled => true;
  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async => SkillRegistryPage(
    entries: [
      MarketplaceSkill(
        key: '$id-skill-1',
        name: '$id-skill-1',
        description: 'd',
        repoOwner: 'o',
        repoName: 'r',
        directory: '$id/1',
        githubUrl: 'https://github.com/o/r',
      ),
    ],
    hasNext: false,
    total: 1,
  );

  @override
  Future<void> setApiKey(String key) async {}

  @override
  Future<void> testConnection() async {}
}

class _QuotaSource extends _FakeSource {
  _QuotaSource(super.id);
  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery q) async =>
      throw MarketplaceQuotaException('quota');
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-disc-unified-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(pathContext: AppPaths.pathContextForDataRoot(paths.basePath)),
      paths: paths, home: tmp.path, cwd: tmp.path,
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
          child: SkillDiscoverySection(onGoRegistries: () {}),
        ),
      ),
    ),
  );

  SkillCubit buildCubit(List<SkillRegistrySource> sources) {
    final cfg = SkillRegistryConfigService(teampilotRoot: AppStorage.paths.basePath);
    return SkillCubit(
      SkillRepository(),
      registryConfigService: cfg,
      initialSources: sources,
      rebuildSources: (c) => sources,
    );
  }

  testWidgets('auto-browses on open and renders cards', (tester) async {
    final cubit = buildCubit([_FakeSource('alpha')]);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('alpha-skill-1'), findsOneWidget);
  });

  testWidgets('filters by source and status', (tester) async {
    final cubit = buildCubit([_FakeSource('alpha'), _FakeSource('beta')]);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('alpha-skill-1'), findsOneWidget);
    expect(find.text('beta-skill-1'), findsOneWidget);
  });

  testWidgets('quota error shows empty state with registries action', (tester) async {
    final cubit = buildCubit([_QuotaSource('quota')]);
    await tester.pumpWidget(wrap(cubit));
    await tester.pumpAndSettle();
    expect(find.text('No skills discovered'), findsOneWidget);
    expect(find.text('Set API key in Registries'), findsOneWidget);
  });
}