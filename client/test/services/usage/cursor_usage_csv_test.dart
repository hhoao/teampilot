import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_import.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/cursor_usage_csv.dart';

const _header =
    'Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,'
    'Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,'
    'Output Tokens,Total Tokens,Cost';

void main() {
  test('parses token split, billed cost, and subscription rows', () {
    final result = parseCursorUsageCsv(
      [
        _header,
        '2026-10-26T10:00:00Z,,,chat,claude-sonnet-4,,100,1000,200,50,1350,\$1.25',
        '2026-10-26T10:01:00Z,,,chat,auto,,0,20,0,5,25,Included',
      ].join('\n'),
    );

    expect(result.events, hasLength(2));
    final first = result.events.first;
    expect(first.cli, CliTool.cursor);
    expect(first.model, 'claude-sonnet-4');
    expect(first.inputTokens, 1000);
    expect(first.cacheCreationTokens, 100);
    expect(first.cacheReadTokens, 200);
    expect(first.outputTokens, 50);
    expect(first.inputSemantics, UsageInputSemantics.fresh);
    expect(first.costMicroUsd, 1250000);
    expect(first.sessionId, cursorImportedSessionId);
    expect(first.requestId, startsWith('cursor-import:'));

    final second = result.events[1];
    expect(second.model, 'cursor-auto');
    expect(second.costMicroUsd, isNull);
    expect(result.rows, 2);
  });

  test('rejects a bad header and inconsistent total', () {
    expect(
      () => parseCursorUsageCsv('Date,Model\n2026-10-26T10:00:00Z,x'),
      throwsFormatException,
    );
    expect(
      () => parseCursorUsageCsv(
        [
          _header,
          '2026-10-26T10:00:00Z,,,chat,claude,,0,10,0,5,999,Free',
        ].join('\n'),
      ),
      throwsFormatException,
    );
  });

  test('handles quoted fields', () {
    final result = parseCursorUsageCsv(
      [
        _header,
        '2026-10-26T10:00:00Z,,,"chat, review",claude,,0,10,0,5,15,Free',
      ].join('\n'),
    );
    expect(result.events.single.outputTokens, 5);
  });
}
