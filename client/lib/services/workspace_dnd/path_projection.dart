import '../session/launch_command_builder.dart';
import 'path_namespace.dart';
import 'runtime_target.dart';
import 'workspace_file_ref.dart';

/// Outcome of projecting one [WorkspaceFileRef] into a [RuntimeTarget].
sealed class PathProjectionResult {
  const PathProjectionResult();
}

/// The path lives on the same machine as the target and was re-expressed in the
/// target's path style. [projectedPath] is ready to hand to the CLI.
class ProjectedPath extends PathProjectionResult {
  const ProjectedPath(this.projectedPath);
  final String projectedPath;
}

/// The path lives on a different machine than the target; it cannot be named
/// locally. The caller defers to a `CrossNamespaceStrategy`.
class CrossNamespacePath extends PathProjectionResult {
  const CrossNamespacePath(this.ref, this.target);
  final WorkspaceFileRef ref;
  final RuntimeTarget target;
}

/// Re-expresses a dragged path so the process inside a target terminal can
/// resolve it. The forward sibling of `FilePathLinkProvider` (which maps
/// terminal output → app filesystem); this maps app filesystem → terminal.
///
/// Pure and namespace-only: it knows nothing about CLIs, quoting, or transport.
/// Same-host style conversions reuse [LaunchCommandBuilder]'s WSL helpers so
/// path translation lives in exactly one place.
class PathProjection {
  const PathProjection();

  PathProjectionResult project(WorkspaceFileRef ref, RuntimeTarget target) {
    final from = ref.namespace;
    final to = target.namespace;

    if (!from.sameHostAs(to)) {
      return CrossNamespacePath(ref, target);
    }
    if (from.style == to.style) {
      return ProjectedPath(ref.nativePath);
    }
    return ProjectedPath(_reStyle(ref.nativePath, from: from, to: to));
  }

  /// Same machine, different spelling: Windows ⇄ POSIX (the WSL boundary).
  String _reStyle(
    String path, {
    required PathNamespace from,
    required PathNamespace to,
  }) {
    if (from.style == PathStyle.windows && to.style == PathStyle.posix) {
      return LaunchCommandBuilder.windowsPathToWsl(path) ?? path;
    }
    if (from.style == PathStyle.posix && to.style == PathStyle.windows) {
      return LaunchCommandBuilder.wslPathToWindows(path) ?? path;
    }
    return path;
  }
}
