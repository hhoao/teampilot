import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import '../../support/in_memory_filesystem.dart';

class _FakeController implements HtmlWebViewController {
  final loaded = <Uri>[];
  int reloads = 0;
  bool disposed = false;

  @override
  Widget buildWidget(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> loadRequest(Uri uri) async {
    loaded.add(uri);
  }

  @override
  Future<void> reload() async {
    reloads++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('start mounts and loads entry uri', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
      controllerFactory: (_) => controller,
    );

    final mount = await session.start();
    expect(mount, isNotNull);
    expect(controller.loaded, hasLength(1));
    expect(controller.loaded.single.path, endsWith('/m/${mount!.mountId}/index.html'));
    await server.dispose();
  });

  test('reload forwards and dispose unmounts', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final session = HtmlPreviewSession(
      htmlDirectory: '/repo',
      entryFileName: 'index.html',
      server: server,
      controllerFactory: (_) => controller,
    );
    final mount = await session.start();

    await session.reload();
    expect(controller.reloads, 1);

    await session.dispose();
    expect(controller.disposed, isTrue);
    expect(server.isServing(mount!.mountId), isFalse);
    await server.dispose();
  });
}
