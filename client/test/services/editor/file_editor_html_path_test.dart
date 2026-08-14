import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';

void main() {
  group('isHtmlPreviewPath', () {
    test('accepts .html and .htm case-insensitively', () {
      expect(isHtmlPreviewPath('/repo/index.html'), isTrue);
      expect(isHtmlPreviewPath('/repo/a/b/page.htm'), isTrue);
      expect(isHtmlPreviewPath('/repo/INDEX.HTML'), isTrue);
    });

    test('rejects other extensions and extensionless', () {
      expect(isHtmlPreviewPath('/repo/app.dart'), isFalse);
      expect(isHtmlPreviewPath('/repo/readme.md'), isFalse);
      expect(isHtmlPreviewPath('/repo/Dockerfile'), isFalse);
      expect(isHtmlPreviewPath('/repo/page.html.tmp'), isFalse);
    });

    test('keeps workbench-openable path rules intact', () {
      expect(isWorkbenchOpenableFilePath('/repo/index.html'), isTrue);
      expect(isWorkbenchOpenableFilePath('/repo/photo.png'), isTrue);
      expect(isWorkbenchOpenableFilePath('/repo/notes.txt'), isTrue);
    });
  });
}
