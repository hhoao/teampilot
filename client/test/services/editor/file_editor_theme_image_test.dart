import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';

void main() {
  test('isImagePreviewPath allowlist', () {
    expect(isImagePreviewPath('/a/b.PNG'), isTrue);
    expect(isImagePreviewPath('/a/photo.jpeg'), isTrue);
    expect(isImagePreviewPath('/a/x.webp'), isTrue);
    expect(isImagePreviewPath('/a/x.gif'), isTrue);
    expect(isImagePreviewPath('/a/x.bmp'), isTrue);
    expect(isImagePreviewPath('/a/x.svg'), isFalse);
    expect(isImagePreviewPath('/a/x.txt'), isFalse);
    expect(isImagePreviewPath('/a/x.heic'), isFalse);
  });

  test('workbench openable is text or image; svg stays text-only', () {
    expect(isWorkbenchOpenableFilePath('/a/x.png'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.dart'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.svg'), isTrue);
    expect(isEditorOpenableFilePath('/a/x.png'), isFalse);
    expect(isEditorOpenableFilePath('/a/x.svg'), isTrue);
    expect(isWorkbenchOpenableFilePath('/a/x.pdf'), isFalse);
  });

  test('kEditorMaxImageBytes is 25 MiB', () {
    expect(kEditorMaxImageBytes, 25 * 1024 * 1024);
  });
}
