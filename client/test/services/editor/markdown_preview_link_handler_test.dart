import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';
import 'package:teampilot/services/editor/markdown_preview_link_handler.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('relative markdown link under workspace opens via opener', () async {
    final fs = InMemoryFilesystem()
      ..files['/repo/docs/a.md'] = '# a\n[b](./b.md)\n'
      ..files['/repo/docs/b.md'] = '# b\n';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final modes = MarkdownViewModeStore();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      markdownViewModes: modes,
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );

    await handleMarkdownPreviewLink(
      href: './b.md',
      markdownFilePath: '/repo/docs/a.md',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      opener: opener,
    );

    expect(workbench.activeTabId('ws')?.filePath, '/repo/docs/b.md');
  });

  test('http links are ignored by path resolution helper path check', () {
    // Smoke: isEditorOpenableFilePath rejects URLs.
    expect(isEditorOpenableFilePath('https://example.com'), isFalse);
  });
}
