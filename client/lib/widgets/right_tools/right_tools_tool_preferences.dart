import 'package:flutter/foundation.dart';

import '../../models/layout_preferences.dart';

/// Layout fields that affect right-tools panel tabs and disk refresh only.
@immutable
class RightToolsToolPreferences {
  const RightToolsToolPreferences({
    required this.fileTreeVisible,
    required this.gitVisible,
    required this.searchVisible,
    required this.membersVisible,
    required this.boardVisible,
  });

  final bool fileTreeVisible;
  final bool gitVisible;
  final bool searchVisible;
  final bool membersVisible;
  final bool boardVisible;

  /// True when any right-tools tab needs [RightToolsLifecycleHost].
  bool get needsLifecycleHost =>
      fileTreeVisible ||
      gitVisible ||
      membersVisible ||
      boardVisible ||
      searchVisible;

  /// True when file-tree or git panels need disk watchers / refresh.
  bool get needsDiskSideEffects => fileTreeVisible || gitVisible;

  factory RightToolsToolPreferences.from(LayoutPreferences preferences) {
    return RightToolsToolPreferences(
      fileTreeVisible: preferences.fileTreeVisible,
      gitVisible: preferences.gitVisible,
      searchVisible: preferences.searchVisible,
      membersVisible: preferences.membersVisible,
      boardVisible: preferences.boardVisible,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RightToolsToolPreferences &&
            fileTreeVisible == other.fileTreeVisible &&
            gitVisible == other.gitVisible &&
            searchVisible == other.searchVisible &&
            membersVisible == other.membersVisible &&
            boardVisible == other.boardVisible;
  }

  @override
  int get hashCode => Object.hash(
    fileTreeVisible,
    gitVisible,
    searchVisible,
    membersVisible,
    boardVisible,
  );
}

/// Visibility + tool tabs for the right-tools pane — ignores sidebar widths,
/// theme, and other [LayoutPreferences] fields so home-sidebar drag does not
/// rebuild file-tree / git.
@immutable
class RightToolsLayoutSlice {
  const RightToolsLayoutSlice({
    required this.rightToolsVisible,
    required this.tools,
  });

  final bool rightToolsVisible;
  final RightToolsToolPreferences tools;

  LayoutPreferences get panelPreferences => LayoutPreferences(
    rightToolsVisible: rightToolsVisible,
    fileTreeVisible: tools.fileTreeVisible,
    gitVisible: tools.gitVisible,
    searchVisible: tools.searchVisible,
    membersVisible: tools.membersVisible,
    boardVisible: tools.boardVisible,
  );

  @override
  bool operator ==(Object other) {
    return other is RightToolsLayoutSlice &&
        rightToolsVisible == other.rightToolsVisible &&
        tools == other.tools;
  }

  @override
  int get hashCode => Object.hash(rightToolsVisible, tools);
}
