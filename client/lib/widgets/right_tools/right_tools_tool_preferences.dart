import 'package:flutter/foundation.dart';

import '../../models/layout_preferences.dart';

/// Layout fields that affect right-tools panel tabs and disk refresh only.
@immutable
class RightToolsToolPreferences {
  const RightToolsToolPreferences({
    required this.fileTreeVisible,
    required this.gitVisible,
    required this.membersVisible,
    required this.boardVisible,
  });

  final bool fileTreeVisible;
  final bool gitVisible;
  final bool membersVisible;
  final bool boardVisible;

  factory RightToolsToolPreferences.from(LayoutPreferences preferences) {
    return RightToolsToolPreferences(
      fileTreeVisible: preferences.fileTreeVisible,
      gitVisible: preferences.gitVisible,
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
            membersVisible == other.membersVisible &&
            boardVisible == other.boardVisible;
  }

  @override
  int get hashCode =>
      Object.hash(fileTreeVisible, gitVisible, membersVisible, boardVisible);
}
