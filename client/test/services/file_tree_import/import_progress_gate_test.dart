import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/file_tree_import/import_progress_gate.dart';

void main() {
  group('shouldShowImportProgress', () {
    test('small local import is silent', () {
      expect(
        shouldShowImportProgress(
          flattenedFileCount: 3,
          maxFileBytes: 1024,
          destIsLocal: true,
        ),
        isFalse,
      );
    });

    test('shows when flattened file count reaches threshold', () {
      expect(
        shouldShowImportProgress(
          flattenedFileCount: 10,
          maxFileBytes: 1024,
          destIsLocal: true,
        ),
        isTrue,
      );
    });

    test('shows when max file size reaches threshold', () {
      expect(
        shouldShowImportProgress(
          flattenedFileCount: 1,
          maxFileBytes: 5 * 1024 * 1024,
          destIsLocal: true,
        ),
        isTrue,
      );
    });

    test('always shows for non-local destination', () {
      expect(
        shouldShowImportProgress(
          flattenedFileCount: 1,
          maxFileBytes: 1024,
          destIsLocal: false,
        ),
        isTrue,
      );
    });
  });
}
