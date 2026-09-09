import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/l10n/l10n_extensions.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/pages/workbench/file_editor_surface.dart';
import 'package:teampilot/pages/workbench/svg_preview_pane.dart';
import 'package:teampilot/services/editor/editor_messages.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/editor/svg_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

const svgSource =
    '<svg xmlns="http://www.w3.org/2000/svg" width="108" height="20">'
    '<rect width="108" height="20" fill="#555"/></svg>';

class _Harness {
  _Harness(this.editor, this.workbench, this.floating, this.opener);

  final EditorCubit editor;
  final WorkbenchCubit workbench;
  final FloatingWorkspaceCubit floating;
  final WorkbenchEditorOpener opener;

  void dispose() {
    editor.close();
    workbench.close();
    floating.close();
  }
}

/// Bounded pumps instead of pumpAndSettle: PhotoView keeps scheduling frames
/// after the contained-scale-to-1:1 clamp, which never settles (same harness
/// convention as svg_preview_pane_test.dart).
Future<void> _pumpSurface(WidgetTester tester, _Harness harness) async {
  await tester.pumpWidget(
    MultiRepositoryProvider(
      providers: [
        RepositoryProvider<WorkbenchEditorOpener>.value(value: harness.opener),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<EditorCubit>.value(value: harness.editor),
          BlocProvider<WorkbenchCubit>.value(value: harness.workbench),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: FileEditorSurface(workspaceId: 'ws', path: '/repo/icon.svg'),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<_Harness> _createHarness(
  WidgetTester tester, {
  String source = svgSource,
}) async {
  final fs = InMemoryFilesystem()..files['/repo/icon.svg'] = source;
  final editor = EditorCubit(fs: fs);
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  final opener = WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    floating: floating,
    markdownViewModes: MarkdownViewModeStore(),
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
  final harness = _Harness(editor, workbench, floating, opener);
  addTearDown(harness.dispose);
  // openFile touches the (in-memory) filesystem through async IO paths that
  // real-time cooperativity requires in widget tests — run inside runAsync
  // (same convention as svg_preview_pane_test.dart).
  await tester.runAsync(() => editor.openFile('ws', '/repo/icon.svg'));
  return harness;
}

void main() {
  testWidgets('svg opens in preview mode by default', (tester) async {
    final harness = await _createHarness(tester);
    await _pumpSurface(tester, harness);

    expect(find.byType(SvgPreviewPane), findsOneWidget);
  });

  testWidgets('edit toggle switches to the source editor', (tester) async {
    final harness = await _createHarness(tester);
    await _pumpSurface(tester, harness);

    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.tap(find.byTooltip(l10n.htmlViewToggleEdit));
    expect(
      harness.opener.svgViewModes.modeFor('/repo/icon.svg'),
      SvgViewMode.edit,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(SvgPreviewPane), findsNothing);
  });

  testWidgets('invalid svg can still switch from preview to source editor', (
    tester,
  ) async {
    final harness = await _createHarness(tester, source: 'not an svg');
    await _pumpSurface(tester, harness);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final errorText = l10n.editorPanelErrorMessage(
      EditorMessage.imageDecodeFailed,
    );

    expect(find.text(errorText), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.htmlViewToggleEdit));
    expect(
      harness.opener.svgViewModes.modeFor('/repo/icon.svg'),
      SvgViewMode.edit,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(SvgPreviewPane), findsNothing);
    expect(find.byType(CodeEditor), findsOneWidget);
    expect(find.text(errorText), findsNothing);

    final controller = harness.editor.controllerFor('ws', '/repo/icon.svg');
    expect(controller, isNotNull);
    controller!.text = svgSource;
    await tester.runAsync(
      () => harness.editor.saveFile('ws', '/repo/icon.svg'),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
      harness.editor.state.bucket('ws').errorByPath['/repo/icon.svg'],
      isNull,
    );
    harness.opener.svgViewModes.setMode('/repo/icon.svg', SvgViewMode.preview);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(SvgPreviewPane), findsOneWidget);
    expect(find.text(errorText), findsNothing);
  });
}
