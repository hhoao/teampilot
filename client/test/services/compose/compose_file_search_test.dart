import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_search.dart';
import 'package:teampilot/services/file_tree/workspace_file_search.dart';

void main() {
  group('mergeComposeCandidates', () {
    test('dirs first (with trailing slash), then files, each alphabetical', () {
      final candidates = mergeComposeCandidates(
        directoryPaths: const ['src/utils', 'src'],
        fileMatches: const [
          WorkspaceFileMatch(
            path: '/ws/src/main.dart',
            name: 'main.dart',
            relativePath: 'src/main.dart',
          ),
          WorkspaceFileMatch(
            path: '/ws/readme.md',
            name: 'readme.md',
            relativePath: 'readme.md',
          ),
        ],
      );

      expect(candidates, hasLength(4));
      expect(candidates[0].isDirectory, isTrue);
      expect(candidates[0].relativePath, 'src/');
      expect(candidates[1].isDirectory, isTrue);
      expect(candidates[1].relativePath, 'src/utils/');
      expect(candidates[2].isDirectory, isFalse);
      expect(candidates[2].relativePath, 'readme.md');
      expect(candidates[3].isDirectory, isFalse);
      expect(candidates[3].relativePath, 'src/main.dart');
    });

    test('insert text keeps the trailing slash for directories', () {
      final candidates = mergeComposeCandidates(
        directoryPaths: const ['lib'],
        fileMatches: const [
          WorkspaceFileMatch(
            path: '/ws/lib/app.dart',
            name: 'app.dart',
            relativePath: 'lib/app.dart',
          ),
        ],
      );
      expect(candidates.first.insertText, '@lib/');
      expect(candidates.last.insertText, '@lib/app.dart');
    });
  });
}
