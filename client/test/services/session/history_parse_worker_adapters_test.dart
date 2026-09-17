import 'dart:convert';
import 'dart:io';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/cli/claude/capabilities/history/compatible_tool_result_enricher.dart';
import 'package:teampilot/services/cli/codex/capabilities/history/ai_transcript.dart';
import 'package:teampilot/services/session/history/history_parse_worker_adapters.dart';

void main() {
  test('dispatches Claude bundle through the canonical adapter', () async {
    final bundle = AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [
        AiTranscriptFragment(
          name: 'basic.jsonl',
          bytes: await File(
            'test/fixtures/session_history/claude/basic.jsonl',
          ).readAsBytes(),
        ),
      ],
    );

    final result = await parseHistoryBundleInWorker(
      adapterId: 'claude',
      bundle: bundle,
    );
    final canonical = await const ClaudeAiTranscriptAdapter().parse(bundle);

    expect(_messageShapes(result.messages), _messageShapes(canonical));
    expect(result.messages.map((message) => message.id), ['u-1', 'a-1']);
    expect(result.messages.last.parts.first, isA<AiTextPart>());
  });

  test('dispatches Codex bundle through the canonical adapter', () async {
    final bundle = AiTranscriptBundle(
      adapterId: 'codex',
      fragments: [
        AiTranscriptFragment(
          name: 'rollout.jsonl',
          bytes: utf8.encode(
            '{"type":"event_msg","payload":{"type":"user_message",'
            '"message":"hi"}}\n'
            '{"type":"event_msg","payload":{"type":"agent_message",'
            '"message":"hello"}}',
          ),
        ),
      ],
    );

    final result = await parseHistoryBundleInWorker(
      adapterId: 'codex',
      bundle: bundle,
    );
    final canonical = await const CodexAiTranscriptAdapter().parse(bundle);

    expect(_messageShapes(result.messages), _messageShapes(canonical));
    expect(result.messages.map((message) => message.id), [
      'codex-0',
      'codex-1',
    ]);
  });

  test('unknown adapter IDs fail without a UI fallback', () async {
    await expectLater(
      () => parseHistoryBundleInWorker(
        adapterId: 'unknown-cli',
        bundle: const AiTranscriptBundle(
          adapterId: 'unknown-cli',
          fragments: [],
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test(
    'Claude-compatible worker enrichment is skipped when no part needs it',
    () async {
      final bundle = AiTranscriptBundle(
        adapterId: 'claude',
        fragments: [
          AiTranscriptFragment(
            name: 'plain.jsonl',
            bytes: utf8.encode(
              '{"type":"user","message":{"role":"user","content":"hello"},'
              '"uuid":"u-1","timestamp":"2026-09-15T00:00:00.000Z"}\n'
              '{"type":"assistant","message":{"role":"assistant",'
              '"content":[{"type":"text","text":"no tools here"}]},'
              '"uuid":"a-1","timestamp":"2026-09-15T00:00:01.000Z"}',
            ),
          ),
        ],
      );

      final result = await parseHistoryBundleInWorker(
        adapterId: 'claude',
        bundle: bundle,
        workerEnricherId: 'claude-compatible',
        sourceToken: 'plain-token',
      );

      expect(result.messages.map((message) => message.id), ['u-1', 'a-1']);
      expect(result.indexSnapshot, isNull);
      expect(result.enrichTime, Duration.zero);
    },
  );

  test('Claude-compatible enricher exposes its stable worker ID', () {
    expect(ClaudeCompatibleToolResultEnricher().workerId, 'claude-compatible');
  });
}

List<({String id, AiRole role, String visibleText})> _messageShapes(
  List<AiMessage> messages,
) => [
  for (final message in messages)
    (
      id: message.id,
      role: message.role,
      visibleText: message.parts
          .whereType<AiTextPart>()
          .map((part) => part.text)
          .join('\n'),
    ),
];
