import '../io/filesystem.dart';
import '../workspace/workspace_tools_scope.dart';
import 'multi_root_content_search.dart';

/// Builds one [ContentSearchSlice] per root per resolved target of [scope].
///
/// Falls back to a single cwd slice on [fallbackFs] when nothing resolved yet
/// (scope still resolving), preserving the pre-multi-root behavior of the
/// search panel.
List<ContentSearchSlice> contentSearchSlicesForScope({
  required WorkspaceToolsScopeState scope,
  required String cwd,
  required Filesystem fallbackFs,
}) {
  final slices = <ContentSearchSlice>[];
  for (final target in scope.targetSlices) {
    final fs = target.tools.context.filesystem;
    for (final root in target.roots) {
      if (root.trim().isEmpty) continue;
      slices.add(
        ContentSearchSlice(
          fs: fs,
          root: root,
          label: fs.pathContext.basename(root),
        ),
      );
    }
  }
  if (slices.isEmpty && cwd.trim().isNotEmpty) {
    slices.add(
      ContentSearchSlice(
        fs: fallbackFs,
        root: cwd,
        label: fallbackFs.pathContext.basename(cwd),
      ),
    );
  }
  return slices;
}
