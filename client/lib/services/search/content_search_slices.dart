import '../io/filesystem.dart';
import '../workspace/workspace_tools_scope.dart';
import 'multi_root_content_search.dart';

/// Builds one [ContentSearchSlice] per root per resolved target of [scope].
///
/// Falls back to a single cwd slice on [fallbackFs] when nothing resolved yet
/// (scope still resolving), preserving the pre-multi-root behavior of the
/// search panel.
///
/// Roots are deduplicated by path string: two targets can expose the same
/// root (e.g. a local folder and its SSH twin), and a duplicate root would
/// search the path twice and emit every file group twice. The first slice in
/// scope order wins.
List<ContentSearchSlice> contentSearchSlicesForScope({
  required WorkspaceToolsScopeState scope,
  required String cwd,
  required Filesystem fallbackFs,
}) {
  final slices = <ContentSearchSlice>[];
  final seenRoots = <String>{};
  for (final target in scope.targetSlices) {
    final fs = target.tools.context.filesystem;
    for (final root in target.roots) {
      if (root.trim().isEmpty) continue;
      if (!seenRoots.add(root)) continue;
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
