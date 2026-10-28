import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/cursor_usage_import.dart';
import '../../models/session_usage.dart';
import '../../models/team_config.dart';

const cursorUsageCsvHeader = [
  'Date',
  'Cloud Agent ID',
  'Automation ID',
  'Kind',
  'Model',
  'Max Mode',
  'Input (w/ Cache Write)',
  'Input (w/o Cache Write)',
  'Cache Read',
  'Output Tokens',
  'Total Tokens',
  'Cost',
];

class CursorUsageCsvResult {
  const CursorUsageCsvResult({
    required this.events,
    required this.firstMs,
    required this.lastMs,
    required this.rows,
  });

  final List<SessionUsageEvent> events;
  final int firstMs;
  final int lastMs;
  final int rows;
}

/// Parses the CSV exported by `cursor.com/dashboard/usage`.
///
/// The export is one row per billed request; `Cost` is Cursor's own USD amount
/// when the row is metered and `Included` / `Free` for subscription rows.
CursorUsageCsvResult parseCursorUsageCsv(String text) {
  final lines = text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));
  final header = _parseCsvLine(lines.isEmpty ? '' : lines.first);
  if (header.length != cursorUsageCsvHeader.length || !_sameHeader(header)) {
    throw const FormatException(
      'not a Cursor usage export (expected the dashboard CSV header)',
    );
  }

  final events = <SessionUsageEvent>[];
  var firstMs = 0;
  var lastMs = 0;
  var rows = 0;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) continue;
    final fields = _parseCsvLine(line);
    if (fields.length != cursorUsageCsvHeader.length) {
      throw FormatException(
        'line ${i + 1}: expected ${cursorUsageCsvHeader.length} fields, '
        'got ${fields.length}',
      );
    }
    rows++;
    final date = fields[0].trim();
    final dateMs = DateTime.tryParse(date)?.toUtc().millisecondsSinceEpoch;
    if (dateMs == null || !date.endsWith('Z')) {
      throw FormatException('line ${i + 1}: Date is not a UTC timestamp');
    }
    final modelRaw = fields[4].trim();
    if (modelRaw.isEmpty) {
      throw FormatException('line ${i + 1}: Model is empty');
    }
    final cacheWrite = _tokenCount(fields[6], i + 1, cursorUsageCsvHeader[6]);
    final input = _tokenCount(fields[7], i + 1, cursorUsageCsvHeader[7]);
    final cacheRead = _tokenCount(fields[8], i + 1, cursorUsageCsvHeader[8]);
    final output = _tokenCount(fields[9], i + 1, cursorUsageCsvHeader[9]);
    final totalRaw = fields[10].trim();
    if (totalRaw.isNotEmpty &&
        _tokenCount(totalRaw, i + 1, cursorUsageCsvHeader[10]) !=
            cacheWrite + input + cacheRead + output) {
      throw FormatException(
        'line ${i + 1}: Total Tokens does not match the token columns',
      );
    }
    final hash = sha256
        .convert(utf8.encode(fields.join('\u001f')))
        .toString()
        .substring(0, 32);
    final model = modelRaw == 'auto' ? 'cursor-auto' : modelRaw;
    events.add(
      SessionUsageEvent(
        requestId: 'cursor-import:$hash',
        cli: CliTool.cursor,
        model: model,
        inputTokens: input,
        outputTokens: output,
        cacheReadTokens: cacheRead,
        cacheCreationTokens: cacheWrite,
        inputSemantics: UsageInputSemantics.fresh,
        timestampMs: dateMs,
        sessionId: cursorImportedSessionId,
        costMicroUsd: _billedCostMicroUsd(fields[11]),
      ),
    );
    if (firstMs == 0 || dateMs < firstMs) firstMs = dateMs;
    if (dateMs > lastMs) lastMs = dateMs;
  }
  if (events.isEmpty) {
    throw const FormatException('the Cursor export holds no usage events');
  }
  return CursorUsageCsvResult(
    events: events,
    firstMs: firstMs,
    lastMs: lastMs,
    rows: rows,
  );
}

bool _sameHeader(List<String> header) {
  for (var i = 0; i < cursorUsageCsvHeader.length; i++) {
    if (header[i].trim() != cursorUsageCsvHeader[i]) return false;
  }
  return true;
}

List<String> _parseCsvLine(String line) {
  final fields = <String>[];
  final field = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch == '"' && i + 1 < line.length && line[i + 1] == '"') {
        field.write('"');
        i++;
      } else if (ch == '"') {
        quoted = false;
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      fields.add(field.toString());
      field.clear();
    } else {
      field.write(ch);
    }
  }
  fields.add(field.toString());
  return fields;
}

int _tokenCount(String value, int line, String column) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 0;
  if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
    throw FormatException('line $line: $column is not a token count');
  }
  return int.parse(trimmed);
}

int? _billedCostMicroUsd(String value) {
  final match = RegExp(r'^\$?([\d,]+(?:\.\d+)?)$').firstMatch(value.trim());
  if (match == null) return null;
  final dollars = double.tryParse(match.group(1)!.replaceAll(',', ''));
  if (dollars == null) return null;
  return (dollars * 1000000).round();
}
