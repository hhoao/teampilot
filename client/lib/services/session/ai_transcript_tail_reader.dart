import 'package:ai_message_core/ai_message_core.dart';

import '../cli/registry/capabilities/ai_history_capability.dart';
import '../io/filesystem.dart';
import 'jsonl_decode_worker.dart';

/// 逐行解码注入点(测试用同步实现,生产用 [decodeJsonlLines] 常驻 worker)。
typedef EventDecoder =
    Future<List<Map<String, dynamic>?>> Function(List<List<int>> lines);

/// 尾部锚点增量读取器。
///
/// 状态([TailReaderState])由调用方持有:锚点 = 最后一条"被消费"的行的
/// 整行字节 hash。每次 refresh 读尾部窗口,从锚点行之后逐事件
/// [AiTranscriptLineAppend] 合并进 [TailReaderState.messages](原地变异)。
/// 锚点找不到(重写/压缩/截断)→ 全量重建。
/// EOF 无 `\n` 的残留若能解码为完整 JSON 对象则当一行消费(与全量 parse
/// 一致);半行仍推迟到下次补全。
class AiTranscriptTailReader {
  AiTranscriptTailReader({
    required AiTranscriptLineAppend lineAppend,
    required String fallbackPrefix,
    EventDecoder? decodeEvents,
    this.windowSizes = const [64 * 1024, 256 * 1024],
    this.fullReloadEvery = 30,
  }) : _lineAppend = lineAppend,
       _fallbackPrefix = fallbackPrefix,
       _decodeEvents = decodeEvents ?? decodeJsonlLines;

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
        coalesceAdjacentAssistantsInPlace(state.messages);
        return _counted(applied, state);
      }
    }

    final whole = await fs.readBytes(path);
    if (whole == null || whole.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    final applied = await _consumeFromAnchor(whole, state);
    if (applied != null) {
      coalesceAdjacentAssistantsInPlace(state.messages);
      return _counted(applied, state);
    }
    // 全文件都找不到锚点(重写/压缩/截断)→ 全量重建。
    return _fullReload(fs, path, size, state);
  }

  TailRefreshResult _counted(TailRefreshResult result, TailReaderState state) {
    if (result.changed) state.incrementalCount++;
    return result;
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
    // Suffix windows always end at EOF. A remainder without `\n` is a
    // complete event when it decodes; otherwise it is still mid-write.

    var anchorIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      if (_lineHash(lines[i]) == state.anchorHash) {
        anchorIndex = i;
        break;
      }
    }
    if (anchorIndex < 0) return null;

    final tail = <List<int>>[...lines.sublist(anchorIndex + 1)];
    if (start < bytes.length) {
      tail.add(bytes.sublist(start));
    }
    if (tail.isEmpty) {
      return const TailRefreshResult(changed: false, rebuilt: false);
    }
    final events = await _decodeEvents(tail);
    var consumedAny = false;
    for (var i = 0; i < tail.length; i++) {
      final event = events[i];
      if (event == null) continue;
      final before = state.fallbackSeq;
      final ok = _lineAppend(
        state.messages,
        event,
        fallbackId: () => '$_fallbackPrefix-${state.fallbackSeq++}',
      );
      if (ok) {
        state.anchorHash = _lineHash(tail[i]);
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
    coalesceAdjacentAssistantsInPlace(messages);
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
