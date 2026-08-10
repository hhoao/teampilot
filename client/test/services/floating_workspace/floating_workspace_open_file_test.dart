import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/floating_workspace/floating_workspace_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';
import 'package:teampilot/services/floating_workspace/floating_workspace_open_file.dart';
import 'package:teampilot/services/workbench/workbench_editor_opener.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('pickAndOpenFloatingWorkspaceFile opens selected path via opener', () async {
    final fs = InMemoryFilesystem()..files['/repo/a.txt'] = 'hello';
    final editor = EditorCubit(fs: fs);
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );

    floating.setActiveWorkspace('ws-1');
    final workspaces = [
      Workspace(
        workspaceId: 'ws-1',
        createdAt: 0,
        folders: [const WorkspaceFolder(path: '/repo')],
      ),
    ];

    String? seenInitialDirectory;
    await pickAndOpenFloatingWorkspaceFile(
      floating: floating,
      opener: opener,
      workspaces: workspaces,
      pickFiles: ({
        type = FileType.any,
        allowMultiple = false,
        initialDirectory,
      }) async {
        seenInitialDirectory = initialDirectory;
        return FilePickerResult([
          PlatformFile(name: 'a.txt', size: 1, path: '/repo/a.txt'),
        ]);
      },
    );

    expect(seenInitialDirectory, '/repo');
    expect(
      workbench.state.bar('ws-1').floating.order,
      [WorkbenchTabId.file('/repo/a.txt')],
    );
    expect(editor.state.bucket('ws-1').openFilePaths, ['/repo/a.txt']);
  });

  test('pickAndOpenFloatingWorkspaceFile no-ops when picker cancelled', () async {
    final editor = EditorCubit();
    final workbench = WorkbenchCubit();
    final floating = FloatingWorkspaceCubit();
    addTearDown(editor.close);
    addTearDown(workbench.close);
    addTearDown(floating.close);

    final opener = WorkbenchEditorOpener(
      editor: editor,
      workbench: workbench,
      floating: floating,
      markdownViewModes: MarkdownViewModeStore(),
      readMarkdownOpenMode: () => MarkdownOpenMode.preview,
    );

    floating.setActiveWorkspace('ws-1');
    await pickAndOpenFloatingWorkspaceFile(
      floating: floating,
      opener: opener,
      workspaces: const [],
      pickFiles: ({
        type = FileType.any,
        allowMultiple = false,
        initialDirectory,
      }) async => null,
    );

    expect(workbench.state.bar('ws-1').floating.order, isEmpty);
  });
}
