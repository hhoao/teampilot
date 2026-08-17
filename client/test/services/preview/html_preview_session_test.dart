import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  test('start mounts and exposes entry uri', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
    );

    final mount = await session.start();
    expect(mount, isNotNull);
    expect(
      mount!.entryUri.path,
      endsWith('/m/${mount.mountId}/index.html'),
    );
    await server.dispose();
  });

  test('dispose unmounts', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
    );
    final mount = await session.start();

    await session.dispose();
    expect(server.isServing(mount!.mountId), isFalse);
    await server.dispose();
  });
}
