import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_stream_channel_parts.dart';

const tool = AiToolCallPart(toolCallId: 't1', toolName: 'Read');

void main() {
  test('interleaved thought and text fold onto two channels', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '1'),
      AiReasoningPart(text: 'b'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(2));
    expect((parts[0] as AiReasoningPart).text, 'ab');
    expect((parts[1] as AiTextPart).text, '12');
  });

  test('a tool call starts a new segment', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      tool,
      AiReasoningPart(text: 'b'),
    ]);

    expect(parts, hasLength(3));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect(parts[1], same(tool));
    expect((parts[2] as AiReasoningPart).text, 'b');
  });

  test('channels resume independently after a tool call', () {
    final parts = foldAcpStreamChannelParts(const [
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '1'),
      tool,
      AiReasoningPart(text: 'b'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(5));
    expect((parts[0] as AiReasoningPart).text, 'a');
    expect((parts[1] as AiTextPart).text, '1');
    expect(parts[2], same(tool));
    expect((parts[3] as AiReasoningPart).text, 'b');
    expect((parts[4] as AiTextPart).text, '2');
  });

  test('first-seen type in a segment keeps its position', () {
    final parts = foldAcpStreamChannelParts(const [
      AiTextPart(text: '1'),
      AiReasoningPart(text: 'a'),
      AiTextPart(text: '2'),
    ]);

    expect(parts, hasLength(2));
    expect((parts[0] as AiTextPart).text, '12');
    expect((parts[1] as AiReasoningPart).text, 'a');
  });

  test('append mutates the list in place and skips the other channel', () {
    final out = <AiMessagePart>[
      const AiReasoningPart(text: 'a'),
      const AiTextPart(text: '1'),
    ];
    appendAcpStreamChannelPart(out, const AiReasoningPart(text: 'b'));
    expect(out, hasLength(2));
    expect((out[0] as AiReasoningPart).text, 'ab');
    expect((out[1] as AiTextPart).text, '1');
  });

  test('already-folded channel parts stay the same', () {
    const folded = [
      AiReasoningPart(text: 'ab'),
      AiTextPart(text: '12'),
    ];
    final again = foldAcpStreamChannelParts(folded);
    expect(again, hasLength(2));
    expect((again[0] as AiReasoningPart).text, 'ab');
    expect((again[1] as AiTextPart).text, '12');
  });
}
