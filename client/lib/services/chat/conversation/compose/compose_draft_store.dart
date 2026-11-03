import 'dart:convert';

import '../../../io/filesystem.dart';
import '../../../storage/workspace_layout.dart';
import '../../../../utils/lock_pool.dart';
import 'compose_draft.dart';

/// Persists landing and session compose drafts for one workspace.
///
/// New values are JSON maps (`{text, tokens}`); legacy plain-string drafts are
/// still decoded with no tokens.
class ComposeDraftStore {
  ComposeDraftStore({required Filesystem fs, required String rootPath})
    : _fs = fs,
      _layout = WorkspaceLayout(teampilotRoot: rootPath, fs: fs);

  final Filesystem _fs;
  final WorkspaceLayout _layout;
  static final _workspaceMutationLocks = LockPool();

  Future<ComposeDraft?> loadLanding(String workspaceId) async {
    final document = await _load(workspaceId);
    return ComposeDraft.fromJson(document['landing']);
  }

  Future<void> saveLanding(String workspaceId, ComposeDraft draft) =>
      _mutate(workspaceId, (document) {
        if (draft.isEmpty) {
          document.remove('landing');
        } else {
          document['landing'] = draft.toJson();
        }
      });

  Future<ComposeDraft?> loadSession(String workspaceId, String sessionId) async {
    final document = await _load(workspaceId);
    final sessions = document['sessions'] as Map<String, dynamic>?;
    return ComposeDraft.fromJson(sessions?[sessionId]);
  }

  Future<void> saveSession(
    String workspaceId,
    String sessionId,
    ComposeDraft draft,
  ) => _mutate(workspaceId, (document) {
    final sessions = _sessions(document);
    if (draft.isEmpty) {
      sessions.remove(sessionId);
    } else {
      sessions[sessionId] = draft.toJson();
    }
  });

  Future<void> clearSession(String workspaceId, String sessionId) =>
      _mutate(workspaceId, (document) {
        _sessions(document).remove(sessionId);
      });

  Future<void> _mutate(
    String workspaceId,
    void Function(Map<String, dynamic> document) update,
  ) => _workspaceMutationLocks.synchronized(workspaceId, () async {
    final document = await _load(workspaceId);
    update(document);
    await _save(workspaceId, document);
  });

  Future<Map<String, dynamic>> _load(String workspaceId) async {
    final text = await _fs.readString(_layout.composeDraftsFile(workspaceId));
    if (text == null || text.isEmpty) return {'sessions': <String, dynamic>{}};
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  }

  Map<String, dynamic> _sessions(Map<String, dynamic> document) =>
      document.putIfAbsent('sessions', () => <String, dynamic>{})
          as Map<String, dynamic>;

  Future<void> _save(String workspaceId, Map<String, dynamic> document) async {
    final file = _layout.composeDraftsFile(workspaceId);
    await _fs.ensureDir(_fs.pathContext.dirname(file));
    await _fs.atomicWrite(file, jsonEncode(document));
  }
}
