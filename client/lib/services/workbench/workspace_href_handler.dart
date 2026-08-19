import '../app/external_link_opener.dart';
import '../editor/file_editor_theme.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'workbench_editor_opener.dart';
import 'workspace_file_locator.dart';
import 'workspace_href_classifier.dart';

enum WorkspaceHrefOpenOutcome {
  openedExternal,
  openedFile,
  missing,
  outsideWorkspace,
  notOpenable,
  ignored,
}

bool isPathUnderWorkspaceRoots(String path, List<String> workspaceRoots) {
  if (path.isEmpty) return false;
  final pathCtx = AppPaths.pathContextForDataRoot(path);
  final normalized = pathCtx.normalize(path);
  return workspaceRoots.any((root) {
    if (root.isEmpty) return false;
    final rootCtx = AppPaths.pathContextForDataRoot(root);
    final nRoot = rootCtx.normalize(root);
    return normalized == nRoot || rootCtx.isWithin(nRoot, normalized);
  });
}

class WorkspaceHrefHandler {
  WorkspaceHrefHandler({
    required WorkbenchEditorOpener opener,
    Future<void> Function(Uri uri)? openExternal,
    WorkspaceFileLocator locator = const WorkspaceFileLocator(),
    WorkspaceHrefClassifier classifier = const WorkspaceHrefClassifier(),
  }) : _opener = opener,
       _openExternal = openExternal ?? openExternalUri,
       _locator = locator,
       _classifier = classifier;

  final WorkbenchEditorOpener _opener;
  final Future<void> Function(Uri uri) _openExternal;
  final WorkspaceFileLocator _locator;
  final WorkspaceHrefClassifier _classifier;

  Future<WorkspaceHrefOpenOutcome> open({
    required String href,
    required String workspaceId,
    required List<String> workspaceRoots,
    required List<String> searchBases,
    required Filesystem fs,
  }) async {
    final kind = _classifier.classify(href);
    switch (kind) {
      case WorkspaceHrefIgnored():
        return WorkspaceHrefOpenOutcome.ignored;
      case WorkspaceHrefExternal(:final uri):
        await _openExternal(uri);
        return WorkspaceHrefOpenOutcome.openedExternal;
      case WorkspaceHrefLocalPath(:final rawPath):
        final located = await _locator.locate(
          rawPath: rawPath,
          fs: fs,
          searchBases: searchBases,
        );
        if (located == null) return WorkspaceHrefOpenOutcome.missing;
        if (!isPathUnderWorkspaceRoots(located, workspaceRoots)) {
          return WorkspaceHrefOpenOutcome.outsideWorkspace;
        }
        if (!isWorkbenchOpenableFilePath(located)) {
          return WorkspaceHrefOpenOutcome.notOpenable;
        }
        await _opener.openFile(workspaceId, located, fs: fs);
        return WorkspaceHrefOpenOutcome.openedFile;
    }
  }
}
