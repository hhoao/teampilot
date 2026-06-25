import '../services/io/filesystem.dart';
import '../services/storage/runtime_context.dart';

/// One workspace folder root mounted in [FileTreeCubit] with its work-plane fs.
class FileTreeRootMount {
  const FileTreeRootMount({
    required this.path,
    required this.filesystem,
    this.workContext,
  });

  final String path;
  final Filesystem filesystem;
  final RuntimeContext? workContext;
}
