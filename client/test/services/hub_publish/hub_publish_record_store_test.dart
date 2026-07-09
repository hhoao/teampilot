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
        registryFullName: 'flashskyai/member-hub',
        slug: 'arch',
        prUrl: 'https://github.com/flashskyai/member-hub/pull/1',
        publishedAtMs: 1,
      ),
    );
    expect(
      records.find(kind: HubPublishKind.expert, slug: 'arch')?.prUrl,
      contains('/pull/1'),
    );
  });
}
