import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/preview/html_preview_pane.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import '../../support/in_memory_filesystem.dart';

class _FakeController implements HtmlWebViewController {
  final loaded = <Uri>[];
  int reloads = 0;
  bool disposed = false;
  Object? loadError;

  @override
  Widget buildWidget(BuildContext context) => const SizedBox.shrink();

  @override
  Future<void> loadRequest(Uri uri) async {
    if (loadError != null) throw loadError!;
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

Widget _app({
  required EditorCubit editor,
  required HtmlPreviewPane pane,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: BlocProvider<EditorCubit>(
      create: (_) => editor,
      child: pane,
    ),
  );
}

void main() {
  testWidgets('renders webview surface when load succeeds', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final editor = EditorCubit(fs: fs);

    await tester.pumpWidget(
      _app(
        editor: editor,
        pane: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: server,
            controllerFactory: (_) => controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.loaded, hasLength(1));
    expect(controller.loaded.single.path, contains('/m/'));
    await editor.close();
    // Dispose the real loopback socket in a real-async zone: sockets created
    // inside the widget-test FakeAsync zone otherwise hang test teardown.
    await tester.runAsync(() => server.dispose());
  });

  testWidgets('shows error state when load fails and offers reload', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController()..loadError = StateError('boom');
    final editor = EditorCubit(fs: fs);

    await tester.pumpWidget(
      _app(
        editor: editor,
        pane: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: server,
            controllerFactory: (_) => controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    await editor.close();
    await tester.runAsync(() => server.dispose());
  });

  testWidgets('reloads preview after save (dirty→clean)', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final controller = _FakeController();
    final editor = EditorCubit(fs: fs);

    await tester.pumpWidget(
      _app(
        editor: editor,
        pane: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => HtmlPreviewSession(
            htmlDirectory: dir,
            entryFileName: entry,
            server: server,
            controllerFactory: (_) => controller,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.reloads, 0);
    // DocumentSession schedules real budget timers, so drive fs/editor IO in a
    // real-async zone and pump afterwards for the BlocListener to react.
    await tester.runAsync(
      () => editor.openFile('ws1', '/repo/index.html', fs: fs),
    );
    await tester.pump();
    editor.controllerFor('ws1', '/repo/index.html')!.text = '<p>y</p>';
    await tester.pump();
    expect(editor.state.bucket('ws1').isDirty('/repo/index.html'), isTrue);

    await tester.runAsync(() => editor.saveFile('ws1', '/repo/index.html'));
    await tester.pumpAndSettle();

    expect(controller.reloads, 1);
    await editor.close();
    await tester.runAsync(() => server.dispose());
  });
}