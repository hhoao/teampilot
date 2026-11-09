import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/search/workspace_search_indexes.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('clear drops both file and content indexes', () {
    final indexes = WorkspaceSearchIndexes(
      storage: fakeHomeStorage(filesystem: InMemoryFilesystem()),
    );

    final fileIndex = indexes.fileIndexFor('/srv/app');
    final contentIndex = indexes.contentIndexFor('ws-1');

    indexes.clear();

    expect(identical(indexes.fileIndexFor('/srv/app'), fileIndex), isFalse);
    expect(identical(indexes.contentIndexFor('ws-1'), contentIndex), isFalse);
  });
}
