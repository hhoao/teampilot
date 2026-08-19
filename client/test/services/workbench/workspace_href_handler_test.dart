import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';
import 'package:teampilot/services/workbench/workspace_href_handler.dart';

import '../../support/in_memory_filesystem.dart';

WorkbenchEditorOpener _opener({
  required EditorCubit editor,
  required WorkbenchCubit workbench,
  required FloatingWorkspaceCubit floating,
  required MarkdownViewModeStore modes,
}) {
  return WorkbenchEditorOpener(
    editor: editor,
    workbench: workbench,
    floating: floating,
    markdownViewModes: modes,
    readMarkdownOpenMode: () => MarkdownOpenMode.preview,
  );
}

({
  EditorCubit editor,
  WorkspaceHrefHandler handler,
}) _harness(
  InMemoryFilesystem fs, {
  Future<void> Function(Uri uri)? openExternal,
}) {
  final editor = EditorCubit(fs: fs);
  final workbench = WorkbenchCubit();
  final floating = FloatingWorkspaceCubit();
  final modes = MarkdownViewModeStore();
  addTearDown(editor.close);
  addTearDown(workbench.close);
  addTearDown(floating.close);
  return (
    editor: editor,
    handler: WorkspaceHrefHandler(
      opener: _opener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        modes: modes,
      ),
      openExternal: openExternal,
    ),
  );
}

void main() {
  test('in-workspace relative file opens via opener', () async {
    final fs = InMemoryFilesystem()..files['/repo/src/a.dart'] = 'ok';
    final harness = _harness(fs);

    final outcome = await harness.handler.open(
      href: 'src/a.dart',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      searchBases: const ['/repo'],
      fs: fs,
    );

    expect(outcome, WorkspaceHrefOpenOutcome.openedFile);
    expect(
      harness.editor.state.bucket('ws').openFilePaths,
      contains('/repo/src/a.dart'),
    );
  });

  test('empty workspaceRoots is outsideWorkspace and does not open', () async {
    final fs = InMemoryFilesystem()..files['/repo/src/a.dart'] = 'ok';
    final harness = _harness(fs);

    final outcome = await harness.handler.open(
      href: 'src/a.dart',
      workspaceId: 'ws',
      workspaceRoots: const [],
      searchBases: const ['/repo'],
      fs: fs,
    );

    expect(outcome, WorkspaceHrefOpenOutcome.outsideWorkspace);
    expect(harness.editor.state.bucket('ws').openFilePaths, isEmpty);
  });

  test('missing file is missing', () async {
    final fs = InMemoryFilesystem();
    final harness = _harness(fs);

    final outcome = await harness.handler.open(
      href: 'nope.dart',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      searchBases: const ['/repo'],
      fs: fs,
    );

    expect(outcome, WorkspaceHrefOpenOutcome.missing);
    expect(harness.editor.state.bucket('ws').openFilePaths, isEmpty);
  });

  test('pdf under workspace is notOpenable', () async {
    final fs = InMemoryFilesystem()..files['/repo/a.pdf'] = 'pdf';
    final harness = _harness(fs);

    final outcome = await harness.handler.open(
      href: 'a.pdf',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      searchBases: const ['/repo'],
      fs: fs,
    );

    expect(outcome, WorkspaceHrefOpenOutcome.notOpenable);
    expect(harness.editor.state.bucket('ws').openFilePaths, isEmpty);
  });

  test('injected http openExternal opens externally', () async {
    final fs = InMemoryFilesystem();
    Uri? opened;
    final harness = _harness(
      fs,
      openExternal: (uri) async => opened = uri,
    );

    final outcome = await harness.handler.open(
      href: 'https://example.com/docs',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      searchBases: const ['/repo'],
      fs: fs,
    );

    expect(outcome, WorkspaceHrefOpenOutcome.openedExternal);
    expect(opened?.host, 'example.com');
  });
}
