import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/services/expert_hub/local_expert_writer.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late LocalMemberTemplateStore store;
  late LocalExpertWriter writer;

  setUp(() {
    fs = InMemoryFilesystem();
    store = LocalMemberTemplateStore(fs: fs, dirOverride: '/t');
    writer = LocalExpertWriter(store: store);
  });

  test('save assigns local key and round-trips', () async {
    final saved = await writer.save(
      DiscoverableMember(
        key: '',
        name: 'Arch',
        description: '',
        category: '',
        source: ExpertMemberSource.local,
        member: DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
      ),
    );

    expect(LocalMemberTemplateStore.isLocalKey(saved.key), isTrue);
    expect(await writer.loadAll(), [saved]);
  });

  test('delete removes template', () async {
    final saved = await writer.save(
      DiscoverableMember(
        key: '',
        name: 'Arch',
        description: '',
        category: '',
        source: ExpertMemberSource.local,
        member: DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
      ),
    );

    await writer.delete(saved.key);

    expect(await writer.loadAll(), isEmpty);
  });

  test('getByKey returns saved member', () async {
    final saved = await writer.save(
      DiscoverableMember(
        key: '',
        name: 'Arch',
        description: '',
        category: '',
        source: ExpertMemberSource.local,
        member: DiscoverableTeamMember(name: 'Arch', prompt: 'p'),
      ),
    );

    expect(await writer.getByKey(saved.key), saved);
    expect(await writer.getByKey('teampilot/builtin/developer'), isNull);
  });
}
