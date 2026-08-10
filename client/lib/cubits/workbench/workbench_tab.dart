import 'package:equatable/equatable.dart';

enum WorkbenchTabKind { session, file, diff, shell, run }

/// Floating panel surface id for [kind], or null when the kind hosts on the
/// center strip (session) rather than the floating panel.
String? surfaceIdFor(WorkbenchTabKind kind) => switch (kind) {
  WorkbenchTabKind.shell => 'terminal',
  WorkbenchTabKind.run => 'run',
  WorkbenchTabKind.file => 'filePreview',
  WorkbenchTabKind.diff => 'diffPreview',
  WorkbenchTabKind.session => null,
};

/// Center strip tabs — shell and run live in the floating panel; file/diff may
/// host on center or floating based on [LayoutPreferences.filePreviewHost].
bool isCenterStripWorkbenchTab(WorkbenchTabKind kind) =>
    kind != WorkbenchTabKind.shell && kind != WorkbenchTabKind.run;

/// Which git diff a center-pane diff tab is showing.
enum WorkbenchDiffSource {
  /// Index vs HEAD (`git diff --cached`).
  staged,

  /// Worktree vs index (`git diff`).
  unstaged,

  /// Worktree vs HEAD (uncommitted; Orca "Changes" mode).
  changes,
}

/// Stable identity for one center workbench tab in a workspace.
class WorkbenchTabId extends Equatable {
  const WorkbenchTabId._(this.kind, this.id);

  factory WorkbenchTabId.session(String sessionId) =>
      WorkbenchTabId._(WorkbenchTabKind.session, sessionId);

  factory WorkbenchTabId.file(String absolutePath) =>
      WorkbenchTabId._(WorkbenchTabKind.file, absolutePath);

  factory WorkbenchTabId.diff(
    String absolutePath, {
    required WorkbenchDiffSource source,
  }) => WorkbenchTabId._(
    WorkbenchTabKind.diff,
    diffKey(absolutePath, source: source),
  );

  /// Source Control staged/unstaged rows.
  factory WorkbenchTabId.diffStaged(
    String absolutePath, {
    required bool staged,
  }) => WorkbenchTabId.diff(
    absolutePath,
    source: staged ? WorkbenchDiffSource.staged : WorkbenchDiffSource.unstaged,
  );

  /// File↔Diff toggle: HEAD vs working tree.
  factory WorkbenchTabId.diffChanges(String absolutePath) =>
      WorkbenchTabId.diff(absolutePath, source: WorkbenchDiffSource.changes);

  factory WorkbenchTabId.shell(String entryId) =>
      WorkbenchTabId._(WorkbenchTabKind.shell, entryId);

  factory WorkbenchTabId.run(String runSessionId) =>
      WorkbenchTabId._(WorkbenchTabKind.run, runSessionId);

  static String diffKey(
    String absolutePath, {
    required WorkbenchDiffSource source,
  }) => '$absolutePath::${source.name}';

  static (String path, WorkbenchDiffSource source)? parseDiffKey(String key) {
    for (final source in WorkbenchDiffSource.values) {
      final suffix = '::${source.name}';
      if (key.endsWith(suffix)) {
        return (
          key.substring(0, key.length - suffix.length),
          source,
        );
      }
    }
    return null;
  }

  final WorkbenchTabKind kind;
  final String id;

  String? get sessionId =>
      kind == WorkbenchTabKind.session ? id : null;

  String? get filePath => kind == WorkbenchTabKind.file ? id : null;

  String? get diffAbsolutePath {
    if (kind != WorkbenchTabKind.diff) return null;
    return parseDiffKey(id)?.$1;
  }

  WorkbenchDiffSource? get diffSource {
    if (kind != WorkbenchTabKind.diff) return null;
    return parseDiffKey(id)?.$2;
  }

  bool? get diffStaged {
    final source = diffSource;
    return switch (source) {
      WorkbenchDiffSource.staged => true,
      WorkbenchDiffSource.unstaged => false,
      WorkbenchDiffSource.changes || null => null,
    };
  }

  @override
  List<Object?> get props => [kind, id];
}
