import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/hub_publish/hub_publish_record_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('records publish badge fields', () async {
    final fs = InMemoryFilesystem();
    final records = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
    await records.upsert(
      HubPublishRecord(
        kind: HubPublishKind.expert,
        registryFullName: 'hhoao/teampilot-resources/member-hub',
        slug: 'arch',
        prUrl: 'https://github.com/hhoao/teampilot/pull/1',
        publishedAtMs: 1,
        localId: 'local/abc',
      ),
    );
    expect(
      records.find(kind: HubPublishKind.expert, slug: 'arch')?.prUrl,
      contains('/pull/1'),
    );
    expect(
      records.findByLocalId(kind: HubPublishKind.expert, localId: 'local/abc')
          ?.slug,
      'arch',
    );
  });

  test('load restores records for badge lookup', () async {
    final fs = InMemoryFilesystem();
    final writer = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
    await writer.upsert(
      HubPublishRecord(
        kind: HubPublishKind.team,
        registryFullName: 'hhoao/teampilot-resources/team-hub',
        slug: 'alpha',
        prUrl: 'https://github.com/hhoao/teampilot/pull/2',
        publishedAtMs: 2,
        localId: 'team-alpha',
      ),
    );

    final reader = HubPublishRecordStore(fs: fs, pathOverride: '/p.json');
    await reader.load();
    expect(
      reader.findByLocalId(kind: HubPublishKind.team, localId: 'team-alpha')
          ?.prUrl,
      contains('/pull/2'),
    );
  });
}
