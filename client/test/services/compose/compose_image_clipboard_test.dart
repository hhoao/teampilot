import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_image_clipboard.dart';

void main() {
  group('parseClipboardImageFilePaths', () {
    test('parses GNOME copied-files clipboard text', () {
      expect(
        parseClipboardImageFilePaths(
          filePaths: const [],
          clipboardText: 'copy\nfile:///home/user/Pictures/shot.png',
        ),
        ['/home/user/Pictures/shot.png'],
      );
    });

    test('ignores non-image paths from clipboard text', () {
      expect(
        parseClipboardImageFilePaths(
          filePaths: const [],
          clipboardText: 'copy\nfile:///home/user/readme.md',
        ),
        isEmpty,
      );
    });
  });
}
