import 'dart:convert';
import 'dart:isolate';

import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/ai_history_capability.dart';
import '../io/filesystem.dart';

/// 生产 decoder:worker isolate 里批量 jsonDecode。
Future<List<Map<String, dynamic>?>> decodeJsonlLinesIsolate(
  List<List<int>> lines,
) {
  return Isolate.run(() async {
    final out = <Map<String, dynamic>?>[];
    for (final line in lines) {
      out.add(_tryDecode(utf8.decode(line, allowMalformed: true)));
    }
    return out;
  }, debugName: 'transcript-tail-decoder');
}

Map<String, dynamic>? _tryDecode(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

/// 逐行解码注入点(测试用同步实现,生产用 [decodeJsonlLinesIsolate])。
typedef EventDecoder =
    Future<List<Map<String, dynamic>?>> Function(List<List<int>> lines);

/// 尾部锚点增量读取器。
///
/// 状态([TailReaderState])由调用方持有:锚点 = 最后一条"被消费"的行的
/// 整行字节 hash。每次 refresh 读尾部窗口,从锚点行之后逐事件
/// [AiTranscriptLineAppend] 合并进 [TailReaderState.messages](原地变异)。
/// 锚点找不到(重写/压缩/截断)→ 全量重建。
class AiTranscriptTailReader {
  AiTranscriptTailReader({
    required AiTranscriptLineAppend lineAppend,
    required String fallbackPrefix,
    EventDecoder? decodeEvents,
    this.windowSizes = const [64 * 1024, 256 * 1024],
    this.fullReloadEvery = 30,
  }) : _lineAppend = lineAppend,
       _fallbackPrefix = fallbackPrefix,
       _decodeEvents = decodeEvents ?? decodeJsonlLinesIsolate;

  final AiTranscriptLineAppend _lineAppend;

  /// fallback id 前缀,必须与 adapter 全量 parse 的 `'$cli-${seq}'` 一致
  /// (Claude→'claude',Codex→'codex',Cursor→'cursor'),保证增量与全量
  /// 生成的消息 id 序列完全相同。
  final String _fallbackPrefix;
  final EventDecoder _decodeEvents;
  final List<int> windowSizes;

  /// 每多少次成功增量后强制一次全量校验。
  final int fullReloadEvery;

  static int _lineHash(List<int> line) {
    var hash = 0x811C9DC5;
    for (final b in line) {
      hash = ((hash ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<TailRefreshResult> refresh({
    required Filesystem fs,
    required String path,
    required TailReaderState state,
    bool force = false,
  }) async {
    final stat = await fs.stat(path);
    if (!stat.exists || stat.isDirectory) {
      state.path = null;
      state.anchorHash = null;
      state.messages = [];
      state.incrementalCount = 0;
      return const TailRefreshResult(changed: false, rebuilt: true);
    }
    final size = stat.size ?? 0;
    final pathChanged = state.path != path;
    state.path = path;

    if (force || pathChanged || state.anchorHash == null) {
      return _fullReload(fs, path, size, state);
    }

    if (state.incrementalCount >= fullReloadEvery) {
      return _fullReload(fs, path, size, state);
    }

    // 窗口自适应:优先小窗口,锚点不在再放大,最后全文件。
    for (final window in windowSizes) {
      if (size <= window) break; // 文件比窗口小 → 直接全文件分支
      final start = size - window;
      final tail = await fs.readBytesRange(path, start, window);
      if (tail == null || tail.isEmpty) continue;
      final applied = await _consumeFromAnchor(tail, state);
      if (applied != null) {
        _coalesceAssistantsInPlace(state.messages);
        return _counted(applied, state);
      }
    }

    final whole = await fs.readBytes(path);
    if (whole == null || whole.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    final applied = await _consumeFromAnchor(whole, state);
    if (applied != null) {
      _coalesceAssistantsInPlace(state.messages);
      return _counted(applied, state);
    }
    // 全文件都找不到锚点(重写/压缩/截断)→ 全量重建。
    return _fullReload(fs, path, size, state);
  }

  TailRefreshResult _counted(TailRefreshResult result, TailReaderState state) {
    if (result.changed) state.incrementalCount++;
    return result;
  }

  /// 与全量 adapter 的 [finalizeAiMessagesForHistory] 的 coalesce 语义等价的
  /// **原地**版本:相邻 assistant 消息(不论 message.id)合并为一个,发生在
  /// 列表元素级——列表实例不变,未参与合并的消息实例不变(保住下游
  /// `identical` 快速路径)。增量解析与全量解析必须输出相同消息序列,否则
  /// 相邻不同 id 的 assistant 分片(真实 Claude transcript 中被 user 行
  /// 隔开、或每个 thinking 块独立 id)会在增量下拆成多条。
  static void _coalesceAssistantsInPlace(List<AiMessage> messages) {
    if (messages.length < 2) return;
    var write = 1;
    for (var i = 1; i < messages.length; i++) {
      final prev = messages[write - 1];
      final cur = messages[i];
      if (prev.role == AiRole.assistant && cur.role == AiRole.assistant) {
        messages[write - 1] = prev.copyWith(
          parts: [...prev.parts, ...cur.parts],
        );
      } else {
        messages[write] = cur;
        write++;
      }
    }
    if (write < messages.length) messages.removeRange(write, messages.length);
  }

  /// 尝试在 [bytes] 内找到锚点行并消费其后的新行。
  /// 返回 null 表示窗口内没有锚点(调用方应扩大窗口)。
  Future<TailRefreshResult?> _consumeFromAnchor(
    List<int> bytes,
    TailReaderState state,
  ) async {
    final lines = <List<int>>[];
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        lines.add(bytes.sublist(start, i));
        start = i + 1;
      }
    }
    // 最后一段若以 \n 结尾则无残留,否则是半行(本轮忽略,下轮补全)。

    var anchorIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_lineHash(lines[i]) == state.anchorHash) {
        anchorIndex = i;
        break;
      }
    }
    if (anchorIndex < 0) return null;

    final newLines = lines.sublist(anchorIndex + 1);
    if (newLines.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    final events = await _decodeEvents(newLines);
    var consumedAny = false;
    for (var i = 0; i < newLines.length; i++) {
      final event = events[i];
      if (event == null) continue;
      final before = state.fallbackSeq;
      final ok = _lineAppend(
        state.messages,
        event,
        fallbackId: () => '$_fallbackPrefix-${state.fallbackSeq++}',
      );
      if (ok) {
        state.anchorHash = _lineHash(newLines[i]);
        consumedAny = true;
      } else {
        state.fallbackSeq = before; // 未消费则不消耗序号
      }
    }
    if (!consumedAny) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    return const TailRefreshResult(changed: true, rebuilt: false);
  }

  Future<TailRefreshResult> _fullReload(
    Filesystem fs,
    String path,
    int size,
    TailReaderState state,
  ) async {
    final bytes = await fs.readBytes(path);
    final messages = <AiMessage>[];
    var fallbackSeq = 0;
    int? anchor;
    if (bytes != null) {
      var start = 0;
      for (var i = 0; i <= bytes.length; i++) {
        if (i == bytes.length || bytes[i] == 0x0A) {
          final line = bytes.sublist(start, i);
          start = i + 1;
          if (line.isEmpty) continue;
          final event = (await _decodeEvents([line])).first;
          if (event == null) continue;
          final before = fallbackSeq;
          final ok = _lineAppend(
            messages,
            event,
            fallbackId: () => '$_fallbackPrefix-${fallbackSeq++}',
          );
          if (ok) {
            anchor = _lineHash(line);
          } else {
            fallbackSeq = before;
          }
        }
      }
    }
    _coalesceAssistantsInPlace(messages);
    state.messages = messages;
    state.fallbackSeq = fallbackSeq;
    state.anchorHash = anchor;
    state.incrementalCount = 0;
    return TailRefreshResult(changed: true, rebuilt: true);
  }
}

class TailReaderState {
  String? path;
  int? anchorHash;
  List<AiMessage> messages = [];
  int fallbackSeq = 0;
  int incrementalCount = 0;
}

class TailRefreshResult {
  const TailRefreshResult({required this.changed, required this.rebuilt});
  final bool changed;
  final bool rebuilt;
}
