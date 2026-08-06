import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_clone_service.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
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
  late LocalMemberTemplateStore store;
  late ExpertCloneService service;

  ExpertCloneService make({
    List<DiscoverableMember> catalog = const [],
  }) {
    final source = CompositeExpertHubSource(
      builtIns: const [],
      registry: _FakeExpertHubSource(catalog),
      localStore: store,
    );
    return ExpertCloneService(source: source, localStore: store);
  }

  setUp(() {
    fs = InMemoryFilesystem();
    store = LocalMemberTemplateStore(
      fs: fs,
      dirOverride: AppPaths('/tp').memberHubLocalTemplatesDir,
      uuidFactory: () => 'test-uuid',
    );
    service = make(catalog: [_catalogExpert()]);
  });

  test('catalog expert is cloned to a local key with provenance', () async {
    final out = await service.clone(
      expertKey: 'acme/experts/pm',
      originTeamKey: 'acme/teams/squad',
    );

    expect(out, isNotNull);
    expect(out!.cloned, isTrue);
    expect(out.key, 'local/test-uuid');

    final saved = await store.getByKey('local/test-uuid');
    expect(saved, isNotNull);
    expect(saved!.catalogKey, 'acme/experts/pm');
    expect(saved.originTeamKey, 'acme/teams/squad');
    expect(saved.name, 'Product Manager');
  });

  test('built-in expert is kept, not cloned', () async {
    final out = await service.clone(expertKey: 'teampilot/builtin/team-lead');

    expect(out, isNotNull);
    expect(out!.key, 'teampilot/builtin/team-lead');
    expect(out.cloned, isFalse);
    expect(await store.loadAll(), isEmpty);
  });

  test('existing local key is kept', () async {
    await store.save(_catalogExpert(key: 'local/existing'));

    final out = await service.clone(expertKey: 'local/existing');

    expect(out, isNotNull);
    expect(out!.key, 'local/existing');
    expect(out.cloned, isFalse);
  });

  test('dangling local key is a failure', () async {
    final out = await service.clone(expertKey: 'local/gone');
    expect(out, isNull);
  });

  test('unresolvable catalog key is a failure', () async {
    final out = await service.clone(expertKey: 'acme/experts/nope');
    expect(out, isNull);
  });

  test('reuses an existing local copy from the same catalogKey', () async {
    final first = await service.clone(expertKey: 'acme/experts/pm');
    expect(first!.key, 'local/test-uuid');

    // A fresh service (new run) sees the already-saved local copy.
    final out = await make(catalog: [_catalogExpert()]).clone(
      expertKey: 'acme/experts/pm',
    );
    expect(out, isNotNull);
    expect(out!.key, 'local/test-uuid');
    expect(out.cloned, isFalse);
    expect(await store.loadAll(), hasLength(1));
  });

  test('same expert referenced twice in one run is cloned once', () async {
    final out1 = await service.clone(expertKey: 'acme/experts/pm');
    final out2 = await service.clone(expertKey: 'acme/experts/pm');

    expect(out1!.key, out2!.key);
    expect(await store.loadAll(), hasLength(1));
  });
}
