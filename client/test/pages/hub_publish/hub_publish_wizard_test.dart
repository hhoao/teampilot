import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/hub_publish/show_hub_publish_wizard.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/hub_publish/bundle_provenance_lookup.dart';
import 'package:teampilot/services/hub_publish/github_registry_publisher.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/services/hub_publish/hub_publish_record_store.dart';
import 'package:teampilot/services/hub_publish/hub_publish_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

class _MemoryKv implements SecureKeyValueStore {
  final map = <String, String>{};

  @override
  Future<void> delete(String key) async => map.remove(key);

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

class FakeHubPublishService implements HubPublishApi {
  FakeHubPublishService({this.prUrl = 'https://github.com/hhoao/teampilot/pull/42'});

  final String prUrl;
  var publishExpertCalls = 0;
  var publishTeamCalls = 0;
  Map<String, String>? lastExpertKeyRemap;
  Object? lastError;

  @override
  Future<HubPublishResult> publishExpert({
    required DiscoverableMember member,
    required String slug,
    ExpertHubRegistry? upstream,
    String? author,
    String? category,
    List<String>? skillIds,
    List<String>? pluginIds,
    List<String>? mcpServerIds,
  }) async {
    publishExpertCalls++;
    if (lastError != null) throw lastError!;
    return HubPublishResult(
      prUrl: prUrl,
      registryFullName: 'hhoao/teampilot-resources/member-hub',
      slug: slug,
    );
  }

  @override
  Future<HubPublishResult> publishTeam({
    required TeamProfile team,
    required String slug,
    required String category,
    required Map<String, String> expertKeyRemap,
    TeamHubRegistry? upstream,
    String? author,
  }) async {
    publishTeamCalls++;
    lastExpertKeyRemap = expertKeyRemap;
    if (lastError != null) throw lastError!;
    return HubPublishResult(
      prUrl: prUrl,
      registryFullName: 'hhoao/teampilot-resources/team-hub',
      slug: slug,
    );
  }
}

DiscoverableMember _localExpert() => DiscoverableMember(
  key: 'local/abc',
  name: 'Arch',
  description: 'Architect',
  category: 'Engineering',
  source: ExpertMemberSource.local,
  tags: const {'design'},
  member: const DiscoverableTeamMember(
    name: 'Arch',
    responsibilities: 'design systems',
  ),
  author: 'alice',
);

DiscoverableMember _publishedExpert() => DiscoverableMember(
  key: 'hhoao/teampilot-resources/member-hub/arch',
  name: 'Arch (published)',
  description: '',
  category: 'Engineering',
  source: ExpertMemberSource.registry,
  member: const DiscoverableTeamMember(name: 'Arch', responsibilities: ''),
);

TeamProfile _teamWithLocalExpert({List<String> skillIds = const []}) =>
    TeamProfile(
      id: 'team-1',
      name: 'Platform',
      description: 'Platform team',
      roster: const [
        TeamRosterSlot(id: 'arch', expertKey: 'local/abc'),
      ],
      skillIds: skillIds,
      createdAt: 1,
    );

void _largeSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpWizard(
  WidgetTester tester, {
  required HubPublishKind kind,
  DiscoverableMember? member,
  TeamProfile? team,
  required HubPublishApi publishApi,
  required GithubCredentialsStore credentials,
  BundleProvenanceLookup? lookup,
  List<DiscoverableMember> remapCandidates = const [],
}) async {
  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          theme.colorScheme,
          scale: 1.0,
          controlScale: AppTypographyScale.standard.multiplier,
        ),
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                key: const Key('open-wizard'),
                onPressed: () {
                  showHubPublishWizard(
                    context,
                    kind: kind,
                    member: member,
                    team: team,
                    publishApi: publishApi,
                    credentials: credentials,
                    lookup: lookup ??
                        BundleProvenanceLookup(
                          skills: const [],
                          plugins: const [],
                          mcps: const [],
                        ),
                    remapCandidates: remapCandidates,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-wizard')));
  await tester.pumpAndSettle();
}

Future<void> _goNext(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('hub-publish-next')));
  await tester.pumpAndSettle();
}

Future<void> _enterPatViaAdvancedPanel(WidgetTester tester, String token) async {
  await tester.tap(find.text('Use a personal access token'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('github-pat-field')), token);
  await tester.tap(find.text('Save'));
  await tester.pumpAndSettle();
}

void main() {
  late GithubCredentialsStore credentials;
  late FakeHubPublishService fakeApi;

  setUp(() {
    credentials = GithubCredentialsStore(
      kv: _MemoryKv(),
      readEnvToken: () => null,
    );
    fakeApi = FakeHubPublishService();
  });

  testWidgets('missing token shows auth panel and cannot finish without token', (
    tester,
  ) async {
    _largeSurface(tester);
    await _pumpWizard(
      tester,
      kind: HubPublishKind.expert,
      member: _localExpert(),
      publishApi: fakeApi,
      credentials: credentials,
    );

    expect(find.byKey(const Key('hub-publish-auth')), findsOneWidget);
    expect(find.byKey(const Key('github-sign-in')), findsOneWidget);

    final next = tester.widget<FilledButton>(
      find.byKey(const Key('hub-publish-next')),
    );
    expect(next.onPressed, isNull);

    await _goNext(tester);
    expect(find.byKey(const Key('hub-publish-auth')), findsOneWidget);
    expect(fakeApi.publishExpertCalls, 0);

    await _enterPatViaAdvancedPanel(tester, 'ghp_test');
    await _goNext(tester);

    expect(find.byKey(const Key('hub-publish-slug')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('hub-publish-slug')), 'arch');
    await _goNext(tester);

    expect(find.byKey(const Key('hub-publish-publish')), findsOneWidget);
    await tester.tap(find.byKey(const Key('hub-publish-publish')));
    await tester.pumpAndSettle();

    expect(fakeApi.publishExpertCalls, 1);
    expect((await credentials.readStored())?.token, 'ghp_test');
    expect(find.byKey(const Key('hub-publish-pr-url')), findsOneWidget);
    expect(find.textContaining(fakeApi.prUrl), findsOneWidget);
  });

  testWidgets('expert happy path shows PR link', (tester) async {
    _largeSurface(tester);
    await credentials.savePat('ghp_saved');
    await _pumpWizard(
      tester,
      kind: HubPublishKind.expert,
      member: _localExpert(),
      publishApi: fakeApi,
      credentials: credentials,
    );

    await _goNext(tester);
    await tester.enterText(find.byKey(const Key('hub-publish-slug')), 'arch');
    await _goNext(tester);
    await tester.tap(find.byKey(const Key('hub-publish-publish')));
    await tester.pumpAndSettle();

    expect(fakeApi.publishExpertCalls, 1);
    expect(find.byKey(const Key('hub-publish-pr-url')), findsOneWidget);
    expect(find.text(fakeApi.prUrl), findsOneWidget);
  });

  testWidgets('401 on publish returns to auth with expired message', (tester) async {
    _largeSurface(tester);
    await credentials.savePat('ghp_saved');
    fakeApi.lastError = const HubPublishException(
      HubPublishErrorCode.unauthorized,
      'Token expired',
    );
    await _pumpWizard(
      tester,
      kind: HubPublishKind.expert,
      member: _localExpert(),
      publishApi: fakeApi,
      credentials: credentials,
    );

    await _goNext(tester);
    await tester.enterText(find.byKey(const Key('hub-publish-slug')), 'arch');
    await _goNext(tester);
    await tester.tap(find.byKey(const Key('hub-publish-publish')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('hub-publish-auth')), findsOneWidget);
    expect(find.text('GitHub sign-in expired'), findsOneWidget);
    expect(fakeApi.publishExpertCalls, 1);
    expect(await credentials.readStored(), isNull);
  });

  testWidgets(
    'team local expert blocked until remap selected, then can proceed',
    (tester) async {
      _largeSurface(tester);
      await credentials.savePat('ghp_saved');
      final published = _publishedExpert();
      await _pumpWizard(
        tester,
        kind: HubPublishKind.team,
        team: _teamWithLocalExpert(),
        publishApi: fakeApi,
        credentials: credentials,
        remapCandidates: [published],
      );

      await _goNext(tester); // auth → metadata
      await tester.enterText(
        find.byKey(const Key('hub-publish-slug')),
        'platform',
      );
      await tester.enterText(
        find.byKey(const Key('hub-publish-category')),
        'Engineering',
      );
      await _goNext(tester); // metadata → gates

      expect(find.byKey(const Key('hub-publish-gates')), findsOneWidget);
      expect(
        find.byKey(const Key('hub-publish-local-expert-blocked')),
        findsOneWidget,
      );

      await _goNext(tester);
      expect(find.byKey(const Key('hub-publish-gates')), findsOneWidget);
      expect(fakeApi.publishTeamCalls, 0);

      await tester.tap(find.byKey(const Key('hub-publish-remap-local/abc')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(published.name).last);
      await tester.pumpAndSettle();

      await _goNext(tester); // gates → confirm
      expect(find.byKey(const Key('hub-publish-publish')), findsOneWidget);

      await tester.tap(find.byKey(const Key('hub-publish-publish')));
      await tester.pumpAndSettle();

      expect(fakeApi.publishTeamCalls, 1);
      expect(fakeApi.lastExpertKeyRemap, {
        'local/abc': published.key,
      });
      expect(find.byKey(const Key('hub-publish-pr-url')), findsOneWidget);
    },
  );

  testWidgets('team non-portable skill id shows blocked list', (tester) async {
    _largeSurface(tester);
    await credentials.savePat('ghp_saved');
    await _pumpWizard(
      tester,
      kind: HubPublishKind.team,
      team: _teamWithLocalExpert(skillIds: const ['local-only-skill']),
      publishApi: fakeApi,
      credentials: credentials,
      remapCandidates: [_publishedExpert()],
      lookup: BundleProvenanceLookup(
        skills: const [],
        plugins: const [],
        mcps: const [],
      ),
    );

    await _goNext(tester);
    await tester.enterText(
      find.byKey(const Key('hub-publish-slug')),
      'platform',
    );
    await tester.enterText(
      find.byKey(const Key('hub-publish-category')),
      'Engineering',
    );
    await _goNext(tester);

    await tester.tap(find.byKey(const Key('hub-publish-remap-local/abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_publishedExpert().name).last);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('hub-publish-non-portable')),
      findsOneWidget,
    );
    expect(find.textContaining('local-only-skill'), findsOneWidget);

    await _goNext(tester);
    expect(find.byKey(const Key('hub-publish-gates')), findsOneWidget);
    expect(fakeApi.publishTeamCalls, 0);
  });
}
