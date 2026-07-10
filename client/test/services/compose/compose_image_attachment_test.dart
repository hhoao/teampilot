import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_image_attachment.dart';
import 'package:teampilot/services/compose/compose_file_attach.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  group('isComposeImagePath', () {
    test('accepts common raster extensions', () {
      expect(isComposeImagePath('/tmp/photo.PNG'), isTrue);
      expect(isComposeImagePath('/tmp/photo.jpeg'), isTrue);
      expect(isComposeImagePath('/tmp/photo.webp'), isTrue);
      expect(isComposeImagePath('/tmp/photo.gif'), isTrue);
    });

    test('rejects non-image paths', () {
      expect(isComposeImagePath('/tmp/readme.md'), isFalse);
      expect(isComposeImagePath('/tmp/archive.zip'), isFalse);
    });
  });

  group('resolveComposeImageReference', () {
    test('uses relative @ reference for images already under workspace', () async {
      final fs = InMemoryFilesystem();
      const root = '/repo';
      const image = '/repo/docs/screenshot.png';
      await fs.writeBytes(image, [1, 2, 3]);

      final ref = await resolveComposeImageReference(
        absolutePath: image,
        workspaceRoot: root,
      );

      expect(ref, '@docs/screenshot.png');
    });

    test('keeps original absolute path for external images', () async {
      final fs = InMemoryFilesystem();
      const root = '/repo';
      const external = '/tmp/paste.png';
      await fs.writeBytes(external, [9, 8, 7]);

      final ref = await resolveComposeImageReference(
        absolutePath: external,
        workspaceRoot: root,
      );

      expect(ref, '@/tmp/paste.png');
      expect((await fs.stat('$root/.teampilot/attachments')).exists, isFalse);
      expect((await fs.stat('/docs/TeamPilot/Attachments')).exists, isFalse);
    });

    test('returns null for non-image paths', () async {
      final fs = InMemoryFilesystem();
      await fs.writeString('/tmp/note.txt', 'hello');

      final ref = await resolveComposeImageReference(
        absolutePath: '/tmp/note.txt',
        workspaceRoot: '/repo',
      );

      expect(ref, isNull);
    });
  });

  group('importComposeImageBytes', () {
    test('writes bytes under Documents/TeamPilot/Attachments', () async {
      final fs = InMemoryFilesystem();
      const attachmentsDir = '/docs/TeamPilot/Attachments';
      const workspaceRoot = '/repo';

      final ref = await importComposeImageBytes(
        bytes: [0x89, 0x50],
        extension: 'png',
        attachmentsDir: attachmentsDir,
        workspaceRoot: workspaceRoot,
        filesystem: fs,
        idGenerator: () => 'clip-1',
      );

      expect(ref, '@/docs/TeamPilot/Attachments/clip-1.png');
      expect(
        await fs.readBytes('$attachmentsDir/clip-1.png'),
        [0x89, 0x50],
      );
    });
  });
}
