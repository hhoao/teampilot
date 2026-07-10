import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_file_attach.dart';
import 'package:teampilot/services/compose/compose_image_clipboard.dart';

import '../../support/in_memory_filesystem.dart';

class _FakeClipboardReader implements ComposeImageClipboardReader {
  _FakeClipboardReader({
    this.bytesPayload,
    this.filePaths = const [],
  });

  final ComposeImageClipboardPayload? bytesPayload;
  final List<String> filePaths;

  @override
  Future<ComposeImageClipboardPayload?> readImageBytes() async => bytesPayload;

  @override
  Future<List<String>> readImageFilePaths() async => filePaths;
}

void main() {
  test('pasteComposeImageAttachment imports clipboard bytes to Attachments', () async {
    final fs = InMemoryFilesystem();
    const root = '/repo';
    const attachmentsDir = '/docs/TeamPilot/Attachments';
    final controller = TextEditingController();

    final pasted = await pasteComposeImageAttachment(
      controller: controller,
      workspaceRoot: root,
      attachmentsDir: attachmentsDir,
      importFilesystem: fs,
      clipboardReader: _FakeClipboardReader(
        bytesPayload: const ComposeImageClipboardPayload(
          bytes: [1, 2, 3],
          extension: 'png',
        ),
      ),
      idGenerator: () => 'paste-1',
    );

    expect(pasted, isTrue);
    expect(controller.text, '@/docs/TeamPilot/Attachments/paste-1.png ');
    expect(await fs.readBytes('$attachmentsDir/paste-1.png'), [1, 2, 3]);
  });

  test('pasteComposeImageAttachment keeps original path for clipboard files', () async {
    final fs = InMemoryFilesystem();
    const root = '/repo';
    const external = '/tmp/clip.png';
    await fs.writeBytes(external, [4, 5, 6]);
    final controller = TextEditingController();

    final pasted = await pasteComposeImageAttachment(
      controller: controller,
      workspaceRoot: root,
      clipboardReader: _FakeClipboardReader(filePaths: [external]),
    );

    expect(pasted, isTrue);
    expect(controller.text, '@/tmp/clip.png ');
    expect((await fs.stat('/docs/TeamPilot/Attachments')).exists, isFalse);
  });
}
