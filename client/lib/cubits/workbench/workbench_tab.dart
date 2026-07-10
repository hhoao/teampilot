import 'package:equatable/equatable.dart';

enum WorkbenchTabKind { session, file, diff }

/// Stable identity for one center workbench tab in a workspace.
class WorkbenchTabId extends Equatable {
  const WorkbenchTabId._(this.kind, this.id);

  factory WorkbenchTabId.session(String sessionId) =>
      WorkbenchTabId._(WorkbenchTabKind.session, sessionId);

  factory WorkbenchTabId.file(String absolutePath) =>
      WorkbenchTabId._(WorkbenchTabKind.file, absolutePath);

  factory WorkbenchTabId.diff(String absolutePath, {required bool staged}) =>
      WorkbenchTabId._(
        WorkbenchTabKind.diff,
        diffKey(absolutePath, staged: staged),
      );

  static String diffKey(String absolutePath, {required bool staged}) =>
      '$absolutePath::${staged ? 'staged' : 'unstaged'}';

  static (String path, bool staged)? parseDiffKey(String key) {
    const stagedSuffix = '::staged';
    const unstagedSuffix = '::unstaged';
    if (key.endsWith(stagedSuffix)) {
      return (
        key.substring(0, key.length - stagedSuffix.length),
        true,
      );
    }
    if (key.endsWith(unstagedSuffix)) {
      return (
        key.substring(0, key.length - unstagedSuffix.length),
        false,
      );
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

  bool? get diffStaged {
    if (kind != WorkbenchTabKind.diff) return null;
    return parseDiffKey(id)?.$2;
  }

  @override
  List<Object?> get props => [kind, id];
}
