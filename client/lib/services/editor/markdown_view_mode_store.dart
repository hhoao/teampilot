import 'package:flutter/foundation.dart';

import '../../models/layout_preferences.dart';

/// In-session Source|Preview mode for markdown editor paths.
///
/// Survives File↔Diff (FileEditorSurface dispose). Not persisted to disk.
class MarkdownViewModeStore extends ChangeNotifier {
  MarkdownViewModeStore();

  final Map<String, MarkdownViewMode> _modes = {};

  MarkdownViewMode? peek(String path) => _modes[path];

  MarkdownViewMode modeFor(String path) =>
      _modes[path] ?? MarkdownViewMode.preview;

  void setMode(String path, MarkdownViewMode mode) {
    if (_modes[path] == mode) return;
    _modes[path] = mode;
    notifyListeners();
  }

  /// Apply [MarkdownOpenMode] seed rules on editor openFile.
  void seedOnOpen(String path, MarkdownOpenMode preference) {
    switch (preference) {
      case MarkdownOpenMode.preview:
        setMode(path, MarkdownViewMode.preview);
      case MarkdownOpenMode.source:
        setMode(path, MarkdownViewMode.source);
      case MarkdownOpenMode.remember:
        if (!_modes.containsKey(path)) {
          setMode(path, MarkdownViewMode.preview);
        }
    }
  }
}

enum MarkdownViewMode { source, preview }

bool isMarkdownEditorPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.md') || lower.endsWith('.markdown');
}
