import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/file_editor_theme.dart';
import 'package:teampilot/services/editor/markdown_preview_link_handler.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

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

void main() {
  test('relative markdown link under workspace opens via opener', () async {
    final fs = InMemoryFilesystem()
      ..files['/repo/docs/a.md'] = '# a\n[b](./b.md)\n'
      ..files['/repo/docs/b.md'] = '# b\n';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    final modes = MarkdownViewModeStore();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    await handleMarkdownPreviewLink(
      href: './b.md',
      markdownFilePath: '/repo/docs/a.md',
      workspaceId: 'ws',
      workspaceRoots: const ['/repo'],
      opener: _opener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        modes: modes,
      ),
    );

    // Must stay POSIX even on Windows hosts (SSH / in-memory roots).
    expect(
      floating.activeBucket.tabs.any(
        (t) => t.payload == '/repo/docs/b.md',
      ),
      isTrue,
    );
    expect(editor.state.bucket('ws').openFilePaths, contains('/repo/docs/b.md'));
  });

  test('relative markdown link with empty workspaceRoots is a no-op', () async {
    final fs = InMemoryFilesystem()
      ..files['/repo/docs/a.md'] = '# a\n'
      ..files['/repo/docs/b.md'] = '# b\n';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    final modes = MarkdownViewModeStore();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    await handleMarkdownPreviewLink(
      href: './b.md',
      markdownFilePath: '/repo/docs/a.md',
      workspaceId: 'ws',
      workspaceRoots: const [],
      opener: _opener(
        editor: editor,
        workbench: workbench,
        floating: floating,
        modes: modes,
      ),
    );

    expect(floating.activeBucket.tabs, isEmpty);
    expect(editor.state.bucket('ws').openFilePaths, isEmpty);
  });

  test('coalesceMarkdownPreviewWorkspaceRoots prefers scope then fallbacks', () {
    expect(
      coalesceMarkdownPreviewWorkspaceRoots(
        scopeRoots: const ['/scope'],
        registryRoots: const ['/registry'],
        folderPaths: const ['/folder'],
      ),
      ['/scope'],
    );
    expect(
      coalesceMarkdownPreviewWorkspaceRoots(
        scopeRoots: const [],
        registryRoots: const ['/registry'],
        folderPaths: const ['/folder'],
      ),
      ['/registry'],
    );
    expect(
      coalesceMarkdownPreviewWorkspaceRoots(
        scopeRoots: null,
        registryRoots: null,
        folderPaths: const ['/folder', ''],
      ),
      ['/folder'],
    );
  });

  test('relative image with empty workspaceRoots returns null', () {
    expect(
      resolveMarkdownPreviewImage(
        src: './shot.png',
        markdownFilePath: '/repo/docs/a.md',
        workspaceRoots: const [],
      ),
      isNull,
    );
  });

  test('relative image under workspaceRoots returns FileImage when present', () {
    final dir = Directory.systemTemp.createTempSync('md-preview-img');
    addTearDown(() => dir.deleteSync(recursive: true));
    final pngPath = [dir.path, 'shot.png'].join(Platform.pathSeparator);
    final png = File(pngPath)
      ..writeAsBytesSync(const [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG magic
      ]);
    final md = [dir.path, 'a.md'].join(Platform.pathSeparator);

    final provider = resolveMarkdownPreviewImage(
      src: './shot.png',
      markdownFilePath: md,
      workspaceRoots: [dir.path],
    );

    expect(provider, isA<FileImage>());
    expect((provider! as FileImage).file.path, png.path);
  });

  test('http links are ignored by path resolution helper path check', () {
    // Smoke: isEditorOpenableFilePath rejects URLs.
    expect(isEditorOpenableFilePath('https://example.com'), isFalse);
  });
}
