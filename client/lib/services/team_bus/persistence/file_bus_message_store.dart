import 'dart:convert';

import '../../io/filesystem.dart';
import '../../io/local_filesystem.dart';
import '../../team/claude_team_roster_service.dart';
import 'bus_message_page.dart';
import 'bus_message_record.dart';
import 'bus_message_store.dart';
import '../team_message.dart';

/// JSONL 冷层：`{mailRoot}/{memberSlug}.jsonl`，append + 全量读分页（session 规模够用）。
class FileBusMessageStore implements BusMessageStore {
  FileBusMessageStore({
    required this.mailRoot,
    Filesystem? fs,
    int Function()? clock,
  }) : _fs = fs ?? LocalFilesystem(),
       _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String mailRoot;
  final Filesystem _fs;
  final int Function() _clock;
  final Map<String, Future<void>> _locks = {};

  Future<T> _locked<T>(String memberId, Future<T> Function() fn) {
    final prev = _locks[memberId] ?? Future<void>.value();
    late Future<T> result;
    final next = prev.then((_) => result);
    _locks[memberId] = next.then((_) {}, onError: (_) {});
    result = fn();
    return result;
  }

  String _memberFile(String memberId) {
    final slug = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
    return _fs.pathContext.join(mailRoot, '$slug.jsonl');
  }

  Future<List<BusMessageRecord>> _readAll(String memberId) async {
    final path = _memberFile(memberId);
    final text = await _fs.readString(path);
    if (text == null || text.trim().isEmpty) return [];
    final out = <BusMessageRecord>[];
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final json = jsonDecode(trimmed);
        if (json is Map) {
          out.add(
            BusMessageRecord.fromJson(Map<String, Object?>.from(json)),
          );
        }
      } on Object {
        continue;
      }
    }
    return out;
  }

  Future<void> _writeAll(String memberId, List<BusMessageRecord> records) async {
    final path = _memberFile(memberId);
    await _fs.ensureDir(mailRoot);
    final body = records.map((r) => jsonEncode(r.toJson())).join('\n');
    await _fs.atomicWrite(path, body.isEmpty ? '' : '$body\n');
  }

  BusMessagePage _slice(
    List<BusMessageRecord> records, {
    required String? afterId,
    required int limit,
    required bool unreadOnly,
  }) {
    final filtered = [
      for (final r in records)
        if (!unreadOnly || r.isUnread) r,
    ];
    final totalUnread = records.where((r) => r.isUnread).length;
    var start = 0;
    if (afterId != null && afterId.isNotEmpty) {
      final anchor = records.indexWhere((r) => r.message.id == afterId);
      if (anchor >= 0) {
        final next = filtered.indexWhere((r) {
          final pos = records.indexWhere((x) => x.message.id == r.message.id);
          return pos > anchor;
        });
        start = next < 0 ? filtered.length : next;
      } else {
        final cursor = filtered.indexWhere((r) => r.message.id == afterId);
        start = cursor < 0 ? filtered.length : cursor + 1;
      }
    }
    final safeLimit = limit.clamp(1, 100);
    final end = (start + safeLimit).clamp(0, filtered.length);
    final slice = filtered.sublist(start, end);
    final hasMore = end < filtered.length;
    return BusMessagePage(
      messages: [for (final r in slice) r.message],
      hasMore: hasMore,
      nextAfterId: hasMore ? slice.last.message.id : null,
      totalUnread: totalUnread,
    );
  }

  @override
  Future<void> append(String memberId, TeamMessage message) async {
    await _locked(memberId, () async {
      await _fs.ensureDir(mailRoot);
      final path = _memberFile(memberId);
      final line = jsonEncode(
        BusMessageRecord(
          message: message,
          createdAt: _clock(),
        ).toJson(),
      );
      // 真正的 append（O(1)），而非整文件读改写。mark-read 仍需全量重写。
      await _fs.appendString(path, '$line\n');
    });
  }

  @override
  Future<BusMessagePage> readPage(
    String memberId, {
    String? afterId,
    int limit = 20,
    bool unreadOnly = true,
    bool markRead = false,
  }) async {
    return _locked(memberId, () async {
      final records = await _readAll(memberId);
      final page = _slice(
        records,
        afterId: afterId,
        limit: limit,
        unreadOnly: unreadOnly,
      );
      if (markRead && page.messages.isNotEmpty) {
        final ids = page.messages.map((m) => m.id).toSet();
        final at = _clock();
        final updated = [
          for (final r in records)
            ids.contains(r.message.id) ? r.markRead(at) : r,
        ];
        await _writeAll(memberId, updated);
      }
      return page;
    });
  }

  @override
  Future<void> markRead(String memberId, Iterable<String> messageIds) async {
    final ids = messageIds.toSet();
    if (ids.isEmpty) return;
    await _locked(memberId, () async {
      final records = await _readAll(memberId);
      final at = _clock();
      var changed = false;
      final updated = <BusMessageRecord>[];
      for (final r in records) {
        if (ids.contains(r.message.id) && r.isUnread) {
          changed = true;
          updated.add(r.markRead(at));
        } else {
          updated.add(r);
        }
      }
      if (changed) await _writeAll(memberId, updated);
    });
  }

  @override
  Future<int> unreadCount(String memberId) async {
    return _locked(memberId, () async {
      final records = await _readAll(memberId);
      return records.where((r) => r.isUnread).length;
    });
  }

  @override
  Future<List<TeamMessage>> loadUnread(String memberId) async {
    return _locked(memberId, () async {
      final records = await _readAll(memberId);
      return [for (final r in records) if (r.isUnread) r.message];
    });
  }
}
