import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import '../../utils/workspace_path_utils.dart';
import 'compose_file_attach.dart';

const _uuid = Uuid();

/// Layout for landing compose image imports under Documents.
abstract final class ComposeImageAttachmentLayout {
  static const teamPilotDirName = 'TeamPilot';
  static const attachmentsDirName = 'Attachments';

  static const allowedExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};

  /// `<Documents>/TeamPilot/Attachments` using [documentsDir].
  static String attachmentsDir(String documentsDir) {
    final ctx = AppPaths.pathContextForDataRoot(documentsDir);
    return ctx.join(
      documentsDir,
      teamPilotDirName,
      attachmentsDirName,
    );
  }
}

typedef ComposeImageIdGenerator = String Function();

String _defaultId() => _uuid.v4();

bool isComposeImagePath(String path) {
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  return ComposeImageAttachmentLayout.allowedExtensions.contains(ext);
}

Future<String?> resolveComposeImageReference({
  required String absolutePath,
  required String workspaceRoot,
}) async {
  if (!isComposeImagePath(absolutePath)) return null;

  final normalized = normalizeWorkspacePath(absolutePath);
  final root = normalizeWorkspacePath(workspaceRoot);
  return formatComposeFileReference(normalized, workspaceRoot: root);
}

Future<String?> importComposeImageBytes({
  required List<int> bytes,
  required String extension,
  required String attachmentsDir,
  required String workspaceRoot,
  required Filesystem filesystem,
  ComposeImageIdGenerator idGenerator = _defaultId,
}) async {
  final ext = extension.toLowerCase();
  if (bytes.isEmpty ||
      !ComposeImageAttachmentLayout.allowedExtensions.contains(ext)) {
    return null;
  }

  await filesystem.ensureDir(attachmentsDir);

  final ctx = filesystem.pathContext;
  final fileName = '${idGenerator()}.$ext';
  final destPath = ctx.join(attachmentsDir, fileName);
  await filesystem.writeBytes(destPath, bytes);

  return formatComposeFileReference(
    destPath,
    workspaceRoot: workspaceRoot,
  );
}
