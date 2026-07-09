import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/my_experts/my_experts_page.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_expert_writer.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/services/hub_publish/hub_publish_record_store.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _FakeSource extends CompositeExpertHubSource {
  _FakeSource() : super(builtIns: const [], registry: _EmptyRegistry());

  @override
  Future<List<DiscoverableMember>> fetchMembers({
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

LaunchProfileCubit _launchCubit({List<TeamProfile> teams = const []}) {
  final cubit = LaunchProfileCubit(
    repository: testLaunchProfileRepository(
      Directory.systemTemp.createTempSync('my_experts_page_'),
    ),
    sessionRepository: SessionRepository(),
    executableResolver: () => 'flashskyai',
  );
  cubit.emit(
    cubit.state.copyWith(
      identities: teams,
      isLoading: false,
    ),
  );
  return cubit;
}

ExpertHubCubit _hubCubit() => ExpertHubCubit(
  source: _FakeSource(),
  loadFavorites: () async => const {},
  saveFavoriteToggle: (_) async => true,
  memberRosterService: MemberRosterService(installSkill: (_) async => null),
  launchProfiles: () => throw UnimplementedError('not used'),
);

void _largeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Widget _host({
  required LocalExpertWriter writer,
  required LaunchProfileCubit launch,
  ExpertHubCubit? hub,
  String? initialMemberKey,
  HubPublishRecordStore? records,
}) {
  final resolvedRecords =
      records ??
      HubPublishRecordStore(
        fs: InMemoryFilesystem(),
        pathOverride: '/hub-publish/records.json',
      );
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<LaunchProfileCubit>.value(value: launch),
        BlocProvider<ExpertHubCubit>.value(value: hub ?? _hubCubit()),
      ],
      child: Scaffold(
        body: MyExpertsPage(
          writer: writer,
          initialMemberKey: initialMemberKey,
          records: resolvedRecords,
        ),
      ),
    ),
  );
}

DiscoverableMember _localExpert({
  required String id,
  required String name,
  String prompt = 'do work',
}) => DiscoverableMember(
  key: 'local/$id',
  name: name,
  description: '$name desc',
  category: 'Custom',
  source: ExpertMemberSource.local,
  member: DiscoverableTeamMember(name: name, prompt: prompt),
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('empty state and create adds a card', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(
        fs: fs,
        dirOverride: '/experts',
        uuidFactory: () => 'new-expert',
      ),
    );
    final launch = _launchCubit();
    addTearDown(() async {
      if (!launch.isClosed) await launch.close();
    });

    await tester.pumpWidget(_host(writer: writer, launch: launch));
    await tester.pumpAndSettle();

    expect(find.text('No experts yet'), findsOneWidget);
    expect(find.text('New Expert'), findsWidgets);

    await tester.tap(find.byKey(const Key('my-experts-create')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'Coder',
    );
    await tester.enterText(
      find.byKey(const Key('expert-editor-prompt')),
      'Write clean code.',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Coder'), findsOneWidget);
    expect(await writer.loadAll(), hasLength(1));
  });

  testWidgets('edit updates expert card', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(fs: fs, dirOverride: '/experts'),
    );
    await writer.save(_localExpert(id: 'e1', name: 'Before'));
    final launch = _launchCubit();
    addTearDown(() async {
      if (!launch.isClosed) await launch.close();
    });

    await tester.pumpWidget(_host(writer: writer, launch: launch));
    await tester.pumpAndSettle();

    expect(find.text('Before'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my-experts-overflow-local/e1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('expert-editor-name')),
      'After',
    );
    await tester.tap(find.byKey(const Key('expert-editor-submit')));
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('delete unreferenced expert removes it', (tester) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(fs: fs, dirOverride: '/experts'),
    );
    await writer.save(_localExpert(id: 'gone', name: 'Disposable'));
    final launch = _launchCubit();
    addTearDown(() async {
      if (!launch.isClosed) await launch.close();
    });

    await tester.pumpWidget(_host(writer: writer, launch: launch));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('my-experts-overflow-local/gone')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirm delete dialog.
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Disposable'), findsNothing);
    expect(await writer.loadAll(), isEmpty);
  });

  testWidgets('delete referenced expert shows error and keeps file', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(fs: fs, dirOverride: '/experts'),
    );
    await writer.save(_localExpert(id: 'used', name: 'In Use'));
    final launch = _launchCubit(
      teams: [
        TeamProfile(
          id: 'team-1',
          name: 'Alpha',
          roster: const [
            TeamRosterSlot(
              id: 'lead',
              expertKey: 'teampilot/builtin/team-lead',
            ),
            TeamRosterSlot(id: 'dev', expertKey: 'local/used'),
          ],
        ),
      ],
    );
    addTearDown(() async {
      if (!launch.isClosed) await launch.close();
    });

    await tester.pumpWidget(_host(writer: writer, launch: launch));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('my-experts-overflow-local/used')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('still referenced'),
      findsOneWidget,
    );
    expect(find.text('In Use'), findsOneWidget);
    expect(await writer.getByKey('local/used'), isNotNull);
  });

  testWidgets('shows PR open badge when HubPublishRecord matches expert', (
    tester,
  ) async {
    _largeSurface(tester);

    final fs = InMemoryFilesystem();
    final writer = LocalExpertWriter(
      store: LocalMemberTemplateStore(fs: fs, dirOverride: '/experts'),
    );
    await writer.save(_localExpert(id: 'e1', name: 'Published One'));
    await writer.save(_localExpert(id: 'e2', name: 'Unpublished'));

    final records = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
    await records.upsert(
      HubPublishRecord(
        kind: HubPublishKind.expert,
        registryFullName: 'flashskyai/member-hub',
        slug: 'published-one',
        prUrl: 'https://github.com/flashskyai/member-hub/pull/3',
        publishedAtMs: 1,
        localId: 'local/e1',
      ),
    );

    final launch = _launchCubit();
    addTearDown(() async {
      if (!launch.isClosed) await launch.close();
    });

    await tester.pumpWidget(
      _host(writer: writer, launch: launch, records: records),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('hub-publish-badge-expert-local/e1')),
      findsOneWidget,
    );
    expect(find.text('PR open'), findsOneWidget);
    expect(
      find.byKey(const Key('hub-publish-badge-expert-local/e2')),
      findsNothing,
    );
  });
}
