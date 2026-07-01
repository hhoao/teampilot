import 'dart:convert';

import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import '../../team/claude_team_roster_service.dart';
import 'bus_message_log.dart';
import '../team_message.dart';

/// JSONL append-only 事件日志:`{mailRoot}/{memberSlug}.jsonl`。
///
/// 每行一个事件:
/// - 投递: `{"t":"msg","seq":N,"id":...,"from":...,"to":...,"content":...,"hop":N,"createdAt":N}`
/// - 已读: `{"t":"read","seq":N,"at":N}`
///
/// 投递与已读都是纯追加(O(1)),无整文件重写。`load` 回放解析未读。
class FileBusMessageLog implements BusMessageLog {
  FileBusMessageLog({required this.mailRoot, Filesystem? fs})
    : _fs = fs ?? LocalFilesystem();

  final String mailRoot;
  final Filesystem _fs;
  final Map<String, Future<void>> _locks = {};

  Future<T> _locked<T>(String memberId, Future<T> Function() fn) {
    final prev = _locks[memberId] ?? Future<void>.value();
    final result = prev.then((_) => fn());
    _locks[memberId] = result.then((_) {}, onError: (_) {});
    return result;
  }

  String _memberFile(String memberId) {
    final slug = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
    return _fs.pathContext.join(mailRoot, '$slug.jsonl');
  }

  Future<void> _appendLine(String memberId, Map<String, Object?> event) {
    return _locked(memberId, () async {
      await _fs.ensureDir(mailRoot);
      await _fs.appendString(_memberFile(memberId), '${jsonEncode(event)}\n');
    });
  }

  @override
  Future<void> appendMessage(
    String memberId,
    int seq,
    TeamMessage message,
    int createdAt,
  ) {
    return _appendLine(memberId, {
      't': 'msg',
      'seq': seq,
      'id': message.id,
      'from': message.from,
      'to': message.to,
      'content': message.content,
      'hop': message.hop,
      'createdAt': createdAt,
    });
  }

  @override
  Future<void> appendRead(String memberId, Iterable<int> seqs, int at) async {
    final list = seqs.toList(growable: false);
    if (list.isEmpty) return;
    await _locked(memberId, () async {
      await _fs.ensureDir(mailRoot);
      final buffer = StringBuffer();
      for (final seq in list) {
        buffer.writeln(jsonEncode({'t': 'read', 'seq': seq, 'at': at}));
      }
      await _fs.appendString(_memberFile(memberId), buffer.toString());
    });
  }

  @override
  Future<List<LoggedMessage>> load(String memberId) {
    return _locked(memberId, () async {
      final text = await _fs.readString(_memberFile(memberId));
      if (text == null || text.trim().isEmpty) return <LoggedMessage>[];
      final bySeq = <int, LoggedMessage>{};
      final readSeqs = <int>{};
      for (final line in const LineSplitter().convert(text)) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        Object? decoded;
        try {
          decoded = jsonDecode(trimmed);
        } on Object {
          continue;
        }
        if (decoded is! Map) continue;
        final event = Map<String, Object?>.from(decoded);
        final seq = (event['seq'] as num?)?.toInt();
        if (seq == null) continue;
        switch (event['t']) {
          case 'msg':
            bySeq[seq] = LoggedMessage(
              seq: seq,
              createdAt: (event['createdAt'] as num?)?.toInt() ?? 0,
              message: TeamMessage(
                id: event['id'] as String? ?? '',
                from: event['from'] as String? ?? '',
                to: event['to'] as String? ?? '',
                content: event['content'] as String? ?? '',
                hop: (event['hop'] as num?)?.toInt() ?? 0,
              ),
            );
          case 'read':
            readSeqs.add(seq);
        }
      }
      for (final seq in readSeqs) {
        bySeq[seq]?.read = true;
      }
      return bySeq.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));
    });
  }
}
