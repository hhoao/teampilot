import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/catalog/catalog_types.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/pages/expert_hub/expert_editor_dialog.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_expert_writer.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import '../../support/stub_member_roster_service.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeSource extends CompositeExpertHubSource {
  _FakeSource() : super(builtIns: const [], registry: _EmptyRegistry());

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => const [];

  @override
  Future<List<CatalogSourceResult<DiscoverableMember>>> fetchMemberSources({
    bool forceRefresh = false,
  }) async => const [];
}

class _EmptyRegistry implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) =>
      Future.value(const []);

  @override
  Future<List<String>> categories({bool forceRefresh = false}) =>
      Future.value(const []);
}

class _SpyWriter extends LocalExpertWriter {
  _SpyWriter({required LocalExpertStore store}) : super(store: store);

  final saved = <DiscoverableMember>[];

  @override
  Future<DiscoverableMember> save(DiscoverableMember member) async {
    final result = await super.save(member);
    saved.add(result);
    return result;
  }
}

class _SpyHubCubit extends ExpertHubCubit {
  _SpyHubCubit()
    : super(
        source: _FakeSource(),
        loadFavorites: () async => const {},
        saveFavoriteToggle: (_) async => true,
        memberRosterService: stubMemberRosterService(),
        launchProfiles: () => throw UnimplementedError('not used'),
      );

  var forceRefreshCalls = 0;

  @override
  Future<void> load({bool forceRefresh = false}) async {
    if (forceRefresh) forceRefreshCalls++;
    await super.load(forceRefresh: forceRefresh);
  }
}

class _HangingHubCubit extends ExpertHubCubit {
  _HangingHubCubit()
    : super(
        source: _FakeSource(),
        loadFavorites: () async => const {},
        saveFavoriteToggle: (_) async => true,
        memberRosterService: stubMemberRosterService(),
        launchProfiles: () => throw UnimplementedError('not used'),
      );

  final Completer<void> _gate = Completer<void>();

  @override
  Future<void> load({bool forceRefresh = false}) => _gate.future;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }
}

void _largeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  testWidgets('submit name+prompt saves via writer and returns member', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );
    final hub = _SpyHubCubit();
    addTearDown(() async {
      if (!hub.isClosed) await hub.close();
    });

    DiscoverableMember? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<ExpertHubCubit>.value(
          value: hub,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showExpertEditorDialog(
                    context,
                    writer: writer,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'Archivist',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Keep the archive tidy.',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-description')),
      'Docs expert',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-category')),
      'Docs',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-playbook')),
      'Read first, then write.',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-tags')),
      'docs, archive',
    );

    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(writer.saved, hasLength(1));
    expect(result, isNotNull);
    expect(result!.name, 'Archivist');
    expect(result!.description, 'Docs expert');
    expect(result!.category, 'Docs');
    expect(result!.member.responsibilities, 'Keep the archive tidy.');
    expect(result!.member.playbook, 'Read first, then write.');
    expect(result!.tags, {'docs', 'archive'});
    expect(LocalExpertStore.isLocalKey(result!.key), isTrue);
    expect(hub.forceRefreshCalls, 1);
  });

  testWidgets('toggling portable skill saves skillDeps', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );

    DiscoverableMember? result;
    final skill = Skill(
      id: 'obra/superpowers:brainstorming',
      name: 'Brainstorming',
      description: '',
      directory: 'skills/brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      installedAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExpertEditorDialog(
                  context,
                  writer: writer,
                  skills: [skill],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'Planner',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Plan carefully.',
    );

    await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
    await tester.pumpAndSettle();

    final switchFinder = find.descendant(
      of: find.byKey(Key('expert-editor-skill-${skill.id}')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-dep-picker-done')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.skillDeps, hasLength(1));
    expect(result!.skillDeps.single.name, 'Brainstorming');
    expect(result!.skillDeps.single.expectedLocalId, skill.id);
  });

  testWidgets('main dialog does not inline skill catalog rows', (tester) async {
    _largeSurface(tester);

    final skill = Skill(
      id: 'obra/superpowers:brainstorming',
      name: 'Brainstorming',
      description: '',
      directory: 'skills/brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      installedAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showExpertEditorDialog(
                  context,
                  writer: _SpyWriter(
                    store: LocalExpertStore(
                      fs: InMemoryFilesystem(),
                      dirOverride: '/t',
                    ),
                  ),
                  skills: [skill],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(Key('expert-editor-skill-${skill.id}')), findsNothing);
    expect(find.byKey(const Key('expert-editor-plugin-p1')), findsNothing);
    expect(find.byKey(const Key('expert-editor-mcp-m1')), findsNothing);
    expect(
      find.byKey(const Key('expert-editor-configure-skills')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('expert-editor-configure-plugins')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('expert-editor-configure-mcp')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('expert-editor-skills-count')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('expert-editor-skills-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('orphan skill counts on main; remove in picker updates count', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );
    const orphan = SkillDependencyRef(
      repoOwner: 'missing',
      repoName: 'pack',
      repoBranch: 'main',
      directory: 'skills/gone',
      name: 'Gone Skill',
    );
    // expectedLocalId == 'missing/pack:gone'
    final initial = DiscoverableMember(
      key: 'local/orphan-expert',
      name: 'Orphaned',
      description: '',
      category: '',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(
        name: 'Orphaned',
        responsibilities: 'prompt',
      ),
      skillDeps: [orphan],
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showExpertEditorDialog(
                  context,
                  writer: writer,
                  initial: initial,
                  skills: const [],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('expert-editor-skills-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('expert-editor-dep-picker-done')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('expert-editor-skills-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('configure skills Done updates count and saves skillDeps', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );

    DiscoverableMember? result;
    final skill = Skill(
      id: 'obra/superpowers:brainstorming',
      name: 'Brainstorming',
      description: '',
      directory: 'skills/brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      installedAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExpertEditorDialog(
                  context,
                  writer: writer,
                  skills: [skill],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
    await tester.pumpAndSettle();

    final switchFinder = find.descendant(
      of: find.byKey(Key('expert-editor-skill-${skill.id}')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-dep-picker-done')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('expert-editor-skills-count')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'Planner',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Plan carefully.',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.skillDeps, hasLength(1));
    expect(result!.skillDeps.single.name, 'Brainstorming');
    expect(result!.skillDeps.single.expectedLocalId, skill.id);
  });

  testWidgets('configure skills Cancel leaves selection unchanged', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );

    DiscoverableMember? result;
    final skill = Skill(
      id: 'obra/superpowers:brainstorming',
      name: 'Brainstorming',
      description: '',
      directory: 'skills/brainstorming',
      repoOwner: 'obra',
      repoName: 'superpowers',
      repoBranch: 'main',
      installedAt: 1,
      updatedAt: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExpertEditorDialog(
                  context,
                  writer: writer,
                  skills: [skill],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-configure-skills')));
    await tester.pumpAndSettle();

    final switchFinder = find.descendant(
      of: find.byKey(Key('expert-editor-skill-${skill.id}')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('expert-editor-dep-picker-cancel')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('expert-editor-skills-count')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('expert-editor-name')), 'X');
    await tester.enterText(find.byKey(const Key('expert-editor-prompt')), 'Y');
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();
    expect(result!.skillDeps, isEmpty);
  });

  testWidgets('edit mode updates existing local expert', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(
        fs: fs,
        dirOverride: '/t',
        uuidFactory: () => 'fixed-id',
      ),
    );
    final existing = await writer.save(
      DiscoverableMember(
        key: 'local/fixed-id',
        name: 'Old Name',
        description: 'old',
        category: 'General',
        source: ExpertMemberSource.local,
        member: const DiscoverableTeamMember(
          name: 'Old Name',
          responsibilities: 'old prompt',
        ),
      ),
    );
    writer.saved.clear();

    DiscoverableMember? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showExpertEditorDialog(
                  context,
                  writer: writer,
                  initial: existing,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Old Name'), findsWidgets);

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'New Name',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'new prompt',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(result?.key, 'local/fixed-id');
    expect(result?.name, 'New Name');
    expect(result?.member.responsibilities, 'new prompt');
    expect(writer.saved.single.key, 'local/fixed-id');
  });

  testWidgets('submit pops even when hub catalog refresh never completes', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );
    final hub = _HangingHubCubit();
    addTearDown(() async {
      hub.release();
      if (!hub.isClosed) await hub.close();
    });

    DiscoverableMember? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider<ExpertHubCubit>.value(
          value: hub,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showExpertEditorDialog(
                    context,
                    writer: writer,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'Closer',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Close the dialog.',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.name, 'Closer');
    expect(find.byKey(const Key('expert-editor-submit')), findsNothing);
  });

  testWidgets('empty name shows field error and does not save', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = _SpyWriter(
      store: LocalExpertStore(fs: fs, dirOverride: '/t'),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                await showExpertEditorDialog(
                  context,
                  writer: writer,
                  skills: const [],
                  plugins: const [],
                  mcps: const [],
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Only prompt',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Name is required.'), findsOneWidget);
    expect(writer.saved, isEmpty);
    expect(find.byKey(const Key('expert-editor-submit')), findsOneWidget);
  });
}
