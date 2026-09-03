import 'package:equatable/equatable.dart';

import '../../models/diff_identity.dart';
import '../../models/git_compare.dart';

enum WorkbenchTabKind {
  session,
  file,
  diff,
  shell,
  run,
  htmlPreview,
  gitGraph,
  gitCompare,
}

/// Floating panel surface id for [kind], or null when the kind hosts on the
/// center strip (session) rather than the floating panel.
String? surfaceIdFor(WorkbenchTabKind kind) => switch (kind) {
  WorkbenchTabKind.shell => 'terminal',
  WorkbenchTabKind.run => 'run',
  WorkbenchTabKind.file => 'filePreview',
  WorkbenchTabKind.diff => 'diffPreview',
  WorkbenchTabKind.htmlPreview => 'htmlPreview',
  WorkbenchTabKind.gitGraph => 'gitGraph',
  WorkbenchTabKind.gitCompare => 'gitCompare',
  WorkbenchTabKind.session => null,
};

/// Center strip tabs — shell, run and htmlPreview live in the floating panel;
/// file/diff may host on center or floating based on
/// [LayoutPreferences.filePreviewHost].
bool isCenterStripWorkbenchTab(WorkbenchTabKind kind) =>
    kind == WorkbenchTabKind.session ||
    kind == WorkbenchTabKind.file ||
    kind == WorkbenchTabKind.diff;

/// Stable identity for one center workbench tab in a workspace.
class WorkbenchTabId extends Equatable {
  const WorkbenchTabId._(this.kind, this.id);

  factory WorkbenchTabId.session(String sessionId) =>
      WorkbenchTabId._(WorkbenchTabKind.session, sessionId);

  factory WorkbenchTabId.file(String absolutePath) =>
      WorkbenchTabId._(WorkbenchTabKind.file, absolutePath);

  factory WorkbenchTabId.diff(DiffIdentity identity) =>
      WorkbenchTabId._(WorkbenchTabKind.diff, identity.storageKey);

  /// Source Control staged/unstaged rows.
  factory WorkbenchTabId.diffStaged(
    String absolutePath, {
    required bool staged,
  }) => WorkbenchTabId.diff(
    ScmDiffIdentity(
      absolutePath,
      staged ? ScmDiffMode.staged : ScmDiffMode.unstaged,
    ),
  );

  /// File↔Diff toggle: HEAD vs working tree.
  factory WorkbenchTabId.diffChanges(String absolutePath) =>
      WorkbenchTabId.diff(ScmDiffIdentity(absolutePath, ScmDiffMode.changes));

  /// Git Graph compare: two arbitrary revisions of one file.
  factory WorkbenchTabId.diffCompare(CompareDiffIdentity identity) =>
      WorkbenchTabId.diff(identity);

  factory WorkbenchTabId.shell(String entryId) =>
      WorkbenchTabId._(WorkbenchTabKind.shell, entryId);

  factory WorkbenchTabId.run(String runSessionId) =>
      WorkbenchTabId._(WorkbenchTabKind.run, runSessionId);

  factory WorkbenchTabId.htmlPreview(String absolutePath) =>
      WorkbenchTabId._(WorkbenchTabKind.htmlPreview, absolutePath);

  /// Git Graph 浮动页：id 即仓库根绝对路径。
  factory WorkbenchTabId.gitGraph(String repoRoot) =>
      WorkbenchTabId._(WorkbenchTabKind.gitGraph, repoRoot);

  /// Git Compare 浮动页：id 编码 repoRoot + 双侧 side，供仅有 id 时通过
  /// [GitCompareSpec.tryParseTabId] 还原 spec。
  factory WorkbenchTabId.gitCompare(GitCompareSpec spec) =>
      WorkbenchTabId._(WorkbenchTabKind.gitCompare, spec.tabId);

  static DiffIdentity? parseDiffStorageKey(String key) =>
      DiffIdentity.parseStorageKey(key);

  final WorkbenchTabKind kind;
  final String id;

  String? get sessionId =>
      kind == WorkbenchTabKind.session ? id : null;

  String? get filePath => kind == WorkbenchTabKind.file ? id : null;

  DiffIdentity? get diffIdentity {
    if (kind != WorkbenchTabKind.diff) return null;
    return parseDiffStorageKey(id);
  }

  String? get diffAbsolutePath => diffIdentity?.absolutePath;

  bool? get diffStaged {
    return switch (diffIdentity) {
      ScmDiffIdentity(mode: ScmDiffMode.staged) => true,
      ScmDiffIdentity(mode: ScmDiffMode.unstaged) => false,
      _ => null,
    };
  }

  @override
  List<Object?> get props => [kind, id];
}
