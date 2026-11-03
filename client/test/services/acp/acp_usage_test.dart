import 'dart:convert';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/acp/acp_chat_transcript.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_usage.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('maps usage_update into AcpUsageUpdate', () {
    final mapped = AcpUsageUpdate.fromAcpd(
      acpd.UsageSessionUpdate(
        used: 120,
        size: 1000,
        cost: const acpd.Cost(amount: 0.25, currency: 'USD'),
      ),
    );

    expect(mapped, isA<AcpUsageUpdate>());
    expect(mapped.used, 120);
    expect(mapped.size, 1000);
    expect(mapped.cost?.amount, 0.25);
    expect(mapped.cost?.currency, 'USD');
  });

  test('UsageSessionUpdate round-trips through the acpd wire shape', () {
    final mapped = AcpUsageUpdate.fromAcpd(
      acpd.UsageSessionUpdate.fromJson(const {
        'sessionUpdate': 'usage_update',
        'used': 4096,
        'size': 1048576,
      }),
    );

    expect(mapped.used, 4096);
    expect(mapped.size, 1048576);
    expect(mapped.cost, isNull);
  });

  test('record derives totals from used and keeps size', () {
    final record = AcpUsageRecord.fromUpdate(
      sessionId: 's1',
      used: 120,
      size: 1000,
      sequence: 1793091272751000,
    );

    expect(record.used, 120);
    expect(record.size, 1000);
    expect(record.totalTokens, 120);
    expect(record.timestampMs, 1793091272751);
  });

  test('appendUsage writes one JSONL record that round-trips', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    const usagePath = '/tp/tool/acp-usage.jsonl';
    final writer = AcpChatTranscriptWriter(
      fs: fs,
      path: '/tp/transcript.jsonl',
      usagePath: usagePath,
    );

    await writer.appendUsage(
      sessionId: 's1',
      used: 120,
      size: 1000,
      model: 'gemini-3.8-flash',
      cost: const acpd.Cost(amount: 0.5, currency: 'USD'),
    );
    await writer.appendUsage(sessionId: 's1', used: 60, size: 1000);

    final raw = await fs.readString(usagePath);
    final lines = const LineSplitter().convert(raw!.trim());
    expect(lines, hasLength(2));

    final first = AcpUsageRecord.fromJson(
      Map<String, Object?>.from(jsonDecode(lines.first) as Map),
    );
    expect(first.sessionId, 's1');
    expect(first.used, 120);
    expect(first.size, 1000);
    expect(first.totalTokens, 120);
    expect(first.model, 'gemini-3.8-flash');
    expect(first.cost, {'amount': 0.5, 'currency': 'USD'});

    final second = AcpUsageRecord.fromJson(
      Map<String, Object?>.from(jsonDecode(lines.last) as Map),
    );
    expect(second.used, 60);
    expect(second.cost, isNull);
    expect(second.sequence, greaterThan(0));
  });

  test('appendUsage is a no-op without a usage path', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final writer = AcpChatTranscriptWriter(
      fs: fs,
      path: '/tp/transcript.jsonl',
    );

    await writer.appendUsage(sessionId: 's1', used: 1, size: 10);

    expect(fs.files, isEmpty);
  });
}
