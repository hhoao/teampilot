import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../storage/app_storage.dart';
import 'file_editor_theme.dart';

/// Builds clipboard text: `relPath:start-end` + fenced code block.
String buildEditorAiContextClipboardText({
  required String relPath,
  required int startLine,
  required int endLine,
  required String language,
  required String code,
}) {
  return '$relPath:$startLine-$endLine\n```$language\n$code\n```';
}

/// Path relative to [AppStorage.cwd], forward slashes, or basename fallback.
String editorRelativePath(String absolutePath) {
  final ctx = AppStorage.fs.pathContext;
  final cwd = AppStorage.cwd;
  try {
    if (ctx.isWithin(cwd, absolutePath)) {
      return ctx.relative(absolutePath, from: cwd).replaceAll('\\', '/');
    }
  } catch (_) {}
  return ctx.basename(absolutePath);
}

String editorLanguageIdForPath(String filePath) {
  return highlightLanguageKeyForPath(filePath) ??
      p.extension(filePath).replaceFirst('.', '').toLowerCase();
}

String codeTextForAiContext(CodeLineEditingController controller) {
  if (controller.selection.isCollapsed) {
    return controller.extentLine.text;
  }
  return controller.selectedText;
}

(int startLine, int endLine) aiContextLineRange(CodeLineSelection selection) {
  return (selection.startIndex + 1, selection.endIndex + 1);
}

String formatEditorAiContext({
  required String filePath,
  required CodeLineEditingController controller,
}) {
  final (startLine, endLine) = aiContextLineRange(controller.selection);
  return buildEditorAiContextClipboardText(
    relPath: editorRelativePath(filePath),
    startLine: startLine,
    endLine: endLine,
    language: editorLanguageIdForPath(filePath),
    code: codeTextForAiContext(controller),
  );
}
