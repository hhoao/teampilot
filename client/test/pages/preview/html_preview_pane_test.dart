import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/preview/html_preview_pane.dart';
import 'package:teampilot/services/preview/html_preview_server.dart';
import 'package:teampilot/services/preview/html_preview_session.dart';
import '../../support/in_memory_filesystem.dart';

class _FailingSession extends HtmlPreviewSession {
  _FailingSession({required HtmlPreviewServer server})
    : super(
        htmlDirectory: '/repo',
        entryFileName: 'index.html',
        server: server,
      );

  @override
  Future<HtmlPreviewMount?> start() async => null;
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
  testWidgets('auto-opens the system browser with the entry uri',
      (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final opened = <Uri>[];
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
          ),
          externalOpener: (uri) async => opened.add(uri),
          openedPaths: <String>{},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(opened.single.path, contains('/m/'));
    expect(find.text('Open in System Browser'), findsOneWidget);
    await editor.close();
    // Dispose the real loopback socket in a real-async zone: sockets created
    // inside the widget-test FakeAsync zone otherwise hang test teardown.
    await tester.runAsync(() => server.dispose());
  });

  testWidgets('does not re-open the browser when the pane remounts',
      (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final opened = <Uri>[];
    final openedPaths = <String>{};
    final editor = EditorCubit(fs: fs);
    Widget build() => _app(
      editor: editor,
      pane: HtmlPreviewPane(
        workspaceId: 'ws1',
        path: '/repo/index.html',
        fs: fs,
        sessionFactory: (dir, entry) => HtmlPreviewSession(
          htmlDirectory: dir,
          entryFileName: entry,
          server: server,
        ),
        externalOpener: (uri) async => opened.add(uri),
        openedPaths: openedPaths,
      ),
    );

    // First mount auto-opens the browser.
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));

    // A rebuild (floating panel minimize/restore, mode switch) remounts the
    // pane; the browser must not open again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(build());
    await tester.pumpAndSettle();

    expect(opened, hasLength(1));
    expect(find.text('Open in System Browser'), findsOneWidget);
    await editor.close();
    await tester.runAsync(() => server.dispose());
  });

  testWidgets('shows error state when the server mount fails', (tester) async {
    final fs = InMemoryFilesystem();
    await fs.writeString('/repo/index.html', '<p>x</p>');
    final server = HtmlPreviewServer(fs: fs);
    final editor = EditorCubit(fs: fs);

    await tester.pumpWidget(
      _app(
        editor: editor,
        pane: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: '/repo/index.html',
          fs: fs,
          sessionFactory: (dir, entry) => _FailingSession(server: server),
          externalOpener: (uri) async {},
          openedPaths: <String>{},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Preview unavailable'), findsOneWidget);
    await editor.close();
    await tester.runAsync(() => server.dispose());
  });

  testWidgets('resolves work-plane fs from editor cubit when fs not provided',
      (tester) async {
    // A windows-context fs makes the resolved fs observable: the session
    // factory receives dirname('C:\\repo\\index.html') = 'C:\\repo' from the
    // editor cubit fs, while the posix AppStorage fallback would yield '.'.
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.windows));
    await fs.writeString(r'C:\repo\index.html', '<p>cubit fs</p>');
    final server = HtmlPreviewServer(fs: fs);
    final opened = <Uri>[];
    final editor = EditorCubit(fs: fs);
    String? factoryDir;

    await tester.pumpWidget(
      _app(
        editor: editor,
        pane: HtmlPreviewPane(
          workspaceId: 'ws1',
          path: r'C:\repo\index.html',
          sessionFactory: (dir, entry) {
            factoryDir = dir;
            return HtmlPreviewSession(
              htmlDirectory: dir,
              entryFileName: 'index.html',
              server: server,
            );
          },
          externalOpener: (uri) async => opened.add(uri),
          openedPaths: <String>{},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(factoryDir, r'C:\repo');
    expect(opened, hasLength(1));
    await editor.close();
    await tester.runAsync(() => server.dispose());
  });
}
