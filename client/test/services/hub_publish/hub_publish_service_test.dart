import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/hub_publish/bundle_provenance_lookup.dart';
import 'package:teampilot/services/hub_publish/github_registry_publisher.dart';
import 'package:teampilot/services/hub_publish/hub_publish_credentials_store.dart';
import 'package:teampilot/services/hub_publish/hub_publish_record_store.dart';
import 'package:teampilot/services/hub_publish/hub_publish_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

import '../../support/in_memory_filesystem.dart';
import 'github_registry_publisher_test.dart';

class _MemoryKv implements SecureKeyValueStore {
  final map = <String, String>{};

  @override
  Future<void> delete(String key) async => map.remove(key);

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;
}

void main() {
  late FakeGithubApi api;
  late HubPublishCredentialsStore credentials;
  late HubPublishRecordStore records;
  late HubPublishService service;
  late BundleProvenanceLookup lookup;

  setUp(() {
    api = FakeGithubApi();
    credentials = HubPublishCredentialsStore(
      kv: _MemoryKv(),
      readEnvToken: () => null,
    );
    records = HubPublishRecordStore(
      fs: InMemoryFilesystem(),
      pathOverride: '/hub-publish/records.json',
    );
    lookup = BundleProvenanceLookup(
      skills: const [],
      plugins: const [],
      mcps: const [],
    );
    service = HubPublishService(
      credentials: credentials,
      records: records,
      publisher: GithubRegistryPublisher(api: api),
      lookup: lookup,
      nowMs: () => 1700000000000,
    );
  });

  test('publishExpert maps, publishes, and upserts record', () async {
    await credentials.saveToken('tok');
    final member = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: 'Architect',
      category: 'Engineering',
      source: ExpertMemberSource.local,
      tags: const {'design'},
      member: const DiscoverableTeamMember(
        name: 'Arch',
        prompt: 'design systems',
      ),
    );

    final result = await service.publishExpert(
      member: member,
      slug: 'arch',
      author: 'alice',
    );

    expect(result.prUrl, api.prHtmlUrl);
    expect(api.writtenPaths, contains('members/arch/member.json'));
    expect(
      records.find(kind: HubPublishKind.expert, slug: 'arch')?.prUrl,
      api.prHtmlUrl,
    );
    expect(
      records.find(kind: HubPublishKind.expert, slug: 'arch')?.registryFullName,
      kDefaultExpertHubRegistry.fullName,
    );
    expect(
      records.find(kind: HubPublishKind.expert, slug: 'arch')?.localId,
      'local/abc',
    );
  });

  test('publishExpert fails when token missing', () async {
    final member = DiscoverableMember(
      key: 'local/abc',
      name: 'Arch',
      description: '',
      category: '',
      source: ExpertMemberSource.local,
      member: const DiscoverableTeamMember(name: 'Arch', prompt: ''),
    );

    await expectLater(
      service.publishExpert(member: member, slug: 'arch'),
      throwsA(
        isA<HubPublishException>().having(
          (e) => e.code,
          'code',
          HubPublishErrorCode.missingToken,
        ),
      ),
    );
    expect(api.writtenPaths, isEmpty);
  });

  test('publishTeam maps, publishes, and upserts record', () async {
    await credentials.saveToken('tok');
    final team = TeamProfile(
      id: 'team-1',
      name: 'Platform',
      description: 'Platform team',
      roster: const [
        TeamRosterSlot(id: 'arch', expertKey: 'flashskyai/member-hub/arch'),
      ],
      createdAt: 1,
    );

    final result = await service.publishTeam(
      team: team,
      slug: 'platform',
      category: 'Engineering',
      expertKeyRemap: const {},
      author: 'alice',
      upstream: kDefaultTeamHubRegistry,
    );

    expect(result.prUrl, isNotEmpty);
    expect(api.writtenPaths, contains('teams/platform/team.json'));
    expect(
      records.find(kind: HubPublishKind.team, slug: 'platform')?.registryFullName,
      kDefaultTeamHubRegistry.fullName,
    );
    expect(
      records.find(kind: HubPublishKind.team, slug: 'platform')?.localId,
      'team-1',
    );
  });

  test('publishTeam blocked when local expert unresolved', () async {
    await credentials.saveToken('tok');
    final team = TeamProfile(
      id: 'team-1',
      name: 'Platform',
      roster: const [TeamRosterSlot(id: 'local', expertKey: 'local/abc')],
      createdAt: 1,
    );

    await expectLater(
      service.publishTeam(
        team: team,
        slug: 'platform',
        category: 'Engineering',
        expertKeyRemap: const {},
      ),
      throwsA(
        isA<HubPublishException>().having(
          (e) => e.code,
          'code',
          HubPublishErrorCode.publishBlocked,
        ),
      ),
    );
    expect(api.writtenPaths, isEmpty);
  });
}
