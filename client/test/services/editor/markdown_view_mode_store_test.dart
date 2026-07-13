import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/editor/markdown_view_mode_store.dart';

void main() {
  test('preview preference always sets preview on open', () {
    final store = MarkdownViewModeStore();
    store.setMode('/a.md', MarkdownViewMode.source);
    store.seedOnOpen('/a.md', MarkdownOpenMode.preview);
    expect(store.modeFor('/a.md'), MarkdownViewMode.preview);
  });

  test('source preference always sets source on open', () {
    final store = MarkdownViewModeStore();
    store.seedOnOpen('/a.md', MarkdownOpenMode.source);
    expect(store.modeFor('/a.md'), MarkdownViewMode.source);
  });

  test('remember keeps existing; seeds preview when missing', () {
    final store = MarkdownViewModeStore();
    store.seedOnOpen('/a.md', MarkdownOpenMode.remember);
    expect(store.modeFor('/a.md'), MarkdownViewMode.preview);
    store.setMode('/a.md', MarkdownViewMode.source);
    store.seedOnOpen('/a.md', MarkdownOpenMode.remember);
    expect(store.modeFor('/a.md'), MarkdownViewMode.source);
  });

  test('isMarkdownEditorPath', () {
    expect(isMarkdownEditorPath('/x/README.md'), isTrue);
    expect(isMarkdownEditorPath('/x/note.markdown'), isTrue);
    expect(isMarkdownEditorPath('/x/a.dart'), isFalse);
  });
}
