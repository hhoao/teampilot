import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_clone_service.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeExpertHubSource implements ExpertHubSource {
  _FakeExpertHubSource(this.members);
  final List<DiscoverableMember> members;
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) async =>
      members;
  @override
  Future<List<String>> categories({bool forceRefresh = false}) async => const [];
}

DiscoverableMember _catalogExpert({String key = 'acme/experts/pm'}) =>
    DiscoverableMember(
      key: key,
      name: 'Product Manager',
      description: 'Plans.',
      category: 'Business',
      source: ExpertMemberSource.registry,
      member: const DiscoverableTeamMember(
        name: 'pm',
        responsibilities: 'You are a PM.',
      ),
    );

void main() {
  late InMemoryFilesystem fs;
  late LocalExpertStore store;
  late ExpertCloneService service;

  setUp(() {
    fs = InMemoryFilesystem();
    store = LocalExpertStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
      uuidFactory: () => 'test-uuid',
    );
    final source = CompositeExpertHubSource(
      builtIns: const [],
      registry: _FakeExpertHubSource([_catalogExpert()]),
      localStore: store,
    );
    service = ExpertCloneService(source: source, store: store);
  });

  test('clones a catalog expert under its key with provenance', () async {
    final out = await service.clone(
      expertKey: 'acme/experts/pm',
      originTeamKey: 'acme/teams/squad',
    );

    expect(out, isNotNull);
    expect(out!.cloned, isTrue);

    final saved = await store.getByKey('acme/experts/pm');
    expect(saved, isNotNull);
    expect(saved!.source, ExpertMemberSource.clone);
    expect(saved.originTeamKey, 'acme/teams/squad');
    expect(saved.clonedAt, greaterThan(0));
  });

  test('reuses an existing clone (O(1) dedup, no duplicate file)', () async {
    await service.clone(expertKey: 'acme/experts/pm');
    final second = await service.clone(expertKey: 'acme/experts/pm');

    expect(second, isNotNull);
    expect(second!.cloned, isFalse);
    expect(await store.loadAll(), hasLength(1));
  });

  test('built-in expert is kept, not cloned', () async {
    final out = await service.clone(expertKey: 'teampilot/builtin/team-lead');

    expect(out, isNotNull);
    expect(out!.cloned, isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('unresolvable key is a failure', () async {
    expect(await service.clone(expertKey: 'acme/experts/nope'), isNull);
  });

  test('empty key is a failure', () async {
    expect(await service.clone(expertKey: '  '), isNull);
  });
}
