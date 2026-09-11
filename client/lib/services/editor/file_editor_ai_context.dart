import 'package:path/path.dart' as p;
import 'package:re_editor/re_editor.dart';

import '../editor_platform/language_registry.dart';
import '../selection_ai/selection_ai_context.dart';
import '../storage/home_storage.dart';

/// Builds clipboard text: `relPath:start-end` + fenced code block.
String buildEditorAiContextClipboardText({
  required String relPath,
  required int startLine,
  required int endLine,
  required String language,
  required String code,
}) {
  return buildFileAiContextClipboardText(
    relPath: relPath,
    startLine: startLine,
    endLine: endLine,
    language: language,
    code: code,
  );
}

/// Path relative to the home working directory ([HomeStorage.cwd]), forward
/// slashes, or basename fallback.
String editorRelativePath(
  String absolutePath, {
  required HomeStorage storage,
}) {
  final ctx = storage.fs.pathContext;
  final cwd = storage.cwd;
  try {
    if (ctx.isWithin(cwd, absolutePath)) {
      return ctx.relative(absolutePath, from: cwd).replaceAll('\\', '/');
    }
  } catch (_) {}
  return ctx.basename(absolutePath);
}

String editorLanguageIdForPath(String filePath) {
  return LanguageRegistry.builtins().resolve(filePath)?.id ??
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
  required HomeStorage storage,
}) {
  final (startLine, endLine) = aiContextLineRange(controller.selection);
  return buildEditorAiContextClipboardText(
    relPath: editorRelativePath(filePath, storage: storage),
    startLine: startLine,
    endLine: endLine,
    language: editorLanguageIdForPath(filePath),
    code: codeTextForAiContext(controller),
  );
}
