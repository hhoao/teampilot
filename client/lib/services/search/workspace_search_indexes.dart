import 'package:ai_message_core/ai_message_core.dart';

import '../../models/workspace.dart';
import '../file_tree/workspace_file_index.dart';
import '../session/workspace_session_content_index.dart';
import '../storage/app_storage.dart';
import '../storage/runtime_layout.dart';

/// App-wide holder for the workspace search indexes — file names
/// ([WorkspaceFileIndexRegistry]) and session transcript content
/// ([WorkspaceSessionContentIndex]) — shared by the Search dialog and the
/// compose `@`-mention picker so each workspace root is indexed once.
///
/// Indexes are cached for the app lifetime and dropped when a workspace tab
/// closes ([disposeWorkspace]); each index also self-freshens via root mtime /
/// transcript cache token + TTL, so no filesystem watch is kept here.
class WorkspaceSearchIndexes {
  WorkspaceSearchIndexes();

  final WorkspaceFileIndexRegistry _fileIndexes = WorkspaceFileIndexRegistry();
  final Map<String, WorkspaceSessionContentIndex> _contentByWorkspace = {};

  /// Chat-history messages keyed by the transcript cache token. Bound after
  /// [AiHistoryLoader] exists so warm can skip a second adapter parse.
  List<AiMessage>? Function({
    required String sessionId,
    required String memberId,
    required String token,
  })?
  cachedHistoryMessages;

  /// Shared fuzzy file-name index for [root], built lazily on first use.
  WorkspaceFileIndex fileIndexFor(String root) =>
      _fileIndexes.indexFor(root, AppStorage.fs);

  /// Shared transcript content index for [workspaceId], built lazily against
  /// the current home storage backend.
  WorkspaceSessionContentIndex contentIndexFor(String workspaceId) {
    return _contentByWorkspace.putIfAbsent(
      workspaceId.trim(),
      () {
        final fs = AppStorage.fs;
        return WorkspaceSessionContentIndex(
          fs: fs,
          layout: RuntimeLayout(
            teampilotRoot: AppStorage.paths.basePath,
            fs: fs,
          ),
          appDataRoot: AppStorage.appDataRoot,
          cachedHistoryMessages: ({
            required sessionId,
            required memberId,
            required token,
          }) =>
              cachedHistoryMessages?.call(
                sessionId: sessionId,
                memberId: memberId,
                token: token,
              ),
        );
      },
    );
  }

  /// Drops the indexes for [workspace] when its editor tab closes.
  void disposeWorkspace(Workspace workspace) {
    for (final folder in workspace.folders) {
      _fileIndexes.remove(folder.path);
    }
    _contentByWorkspace.remove(workspace.workspaceId.trim())?.clear();
  }
}
