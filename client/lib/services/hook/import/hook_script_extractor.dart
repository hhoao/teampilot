import '../../io/filesystem.dart';
import 'hook_json_dialect.dart';

sealed class ScriptExtraction {
  const ScriptExtraction();
}

/// 识别为脚本引用且成功读取：解释器 + 原文件名 + 内容（库内路径重写由
/// [HookImportParser] 完成）。
final class ScriptCopy extends ScriptExtraction {
  const ScriptCopy({
    required this.interpreter,
    required this.fileName,
    required this.content,
  });

  final String interpreter;
  final String fileName;
  final String content;
}

/// 内联命令或路径不可解析：保留原命令字符串。
final class RawCommand extends ScriptExtraction {
  const RawCommand({this.reason});

  /// null = 内联命令；'placeholder' = 含占位符；'unreadable' = 读取失败。
  final String? reason;
}

/// 从 command 字符串识别脚本引用并读取内容（通用、CLI 无关）。
class HookScriptExtractor {
  HookScriptExtractor({required Filesystem fs, this.homeDir})
    : _fs = fs;

  final Filesystem _fs;

  /// `~` 展开的宿主 home；null 时含 `~` 的路径视为不可解析。
  final String? homeDir;

  static const Set<String> interpreters = {
    'bash', 'sh', 'zsh', 'python3', 'python', 'node', 'powershell', 'pwsh',
    'ruby', 'perl',
  };

  Future<ScriptExtraction> extract(String command) async {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return const RawCommand();
    final tokens = _tokenize(trimmed);
    final first = tokens.first;

    String? scriptPath;
    String interpreter = 'bash';
    if (interpreters.contains(first)) {
      if (tokens.length > 1 && tokens[1] == '-c') {
        return const RawCommand();
      }
      for (final token in tokens.skip(1)) {
        final cleaned = stripQuotes(token);
        if (isPathLike(cleaned)) {
          scriptPath = cleaned;
          interpreter = first;
          break;
        }
        if (cleaned.startsWith('-')) continue;
      }
    } else if (isPathLike(stripQuotes(first))) {
      scriptPath = stripQuotes(first);
    } else {
      return const RawCommand();
    }

    if (scriptPath == null) return const RawCommand();
    if (_hasPlaceholder(scriptPath)) return const RawCommand(reason: 'placeholder');

    var resolved = scriptPath;
    if (resolved.startsWith('~')) {
      final home = homeDir;
      if (home == null || home.isEmpty) {
        return const RawCommand(reason: 'placeholder');
      }
      resolved = '$home${resolved.substring(1)}';
    }

    final content = await _fs.readString(resolved);
    if (content == null) return const RawCommand(reason: 'unreadable');

    return ScriptCopy(
      interpreter: interpreter,
      fileName: _fs.pathContext.basename(resolved),
      content: content,
    );
  }

  static bool _hasPlaceholder(String path) =>
      path.contains(r'${') || path.contains(r'$(') || RegExp(r'\$[A-Za-z_]').hasMatch(path);

  /// 按空白切分，但保留引号内空白（如 `python3 "/a b/x.py"`）。
  static List<String> _tokenize(String command) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < command.length; i++) {
      final c = command[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else {
          buffer.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
      } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) tokens.add(buffer.toString());
    return tokens;
  }
}
