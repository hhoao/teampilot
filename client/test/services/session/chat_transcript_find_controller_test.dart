import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/chat_transcript_find_controller.dart';

List<AiMessage> _messages(List<String> texts) => [
  for (final (i, text) in texts.indexed)
    AiMessage(
      id: 'm-$i',
      role: i.isEven ? AiRole.user : AiRole.assistant,
      parts: [AiTextPart(text: text)],
    ),
];

void main() {
  late List<AiMessage> messages;
  late ChatTranscriptFindController controller;

  setUp(() {
    messages = _messages([
      'Plan the alpha feature.',
      'Let me grep for alpha in config.',
      'Alpha is now implemented.',
      'Also fix the beta bug.',
    ]);
    controller = ChatTranscriptFindController(messagesProvider: () => messages);
  });

  tearDown(() => controller.dispose());

  test('empty query yields no hits', () {
    controller.search('   ');
    expect(controller.hasQuery, isFalse);
    expect(controller.hits, isEmpty);
    expect(controller.currentIndex, -1);
  });

  test('finds all case-insensitive matches across messages', () {
    controller.search('alpha');
    expect(controller.hits.length, 3);
    expect(controller.hits[0].messageIndex, 0);
    expect(controller.hits[1].messageIndex, 1);
    expect(controller.hits[2].messageIndex, 2);
    expect(controller.hits[0].messageId, 'm-0');
    expect(controller.hits[0].snippet.toLowerCase(), contains('alpha'));
  });

  test('next/previous wrap around the result list', () {
    controller.search('alpha');
    expect(controller.currentIndex, 0);
    controller.previous();
    expect(controller.currentIndex, 2);
    controller.next();
    expect(controller.currentIndex, 0);
    controller.next();
    expect(controller.currentIndex, 1);
  });

  test('select sets the current match index', () {
    controller.search('alpha');
    expect(controller.hits.length, 3);
    controller.select(1);
    expect(controller.currentIndex, 1);
    controller.select(0);
    expect(controller.currentIndex, 0);
  });

  test('select is a no-op out of range or with no hits', () {
    controller.search('alpha');
    expect(controller.currentIndex, 0);
    controller.select(99);
    expect(controller.currentIndex, 0);
    controller.select(-1);
    expect(controller.currentIndex, 0);

    controller.clear();
    controller.select(0);
    expect(controller.currentIndex, -1);
  });

  test('snippet stays within the matching message', () {
    controller.search('beta');
    expect(controller.hits.single.messageIndex, 3);
    expect(controller.hits.single.snippet, contains('beta'));
  });

  test('clear resets state', () {
    controller.search('alpha');
    controller.clear();
    expect(controller.query, isEmpty);
    expect(controller.hits, isEmpty);
    expect(controller.currentIndex, -1);
  });

  test('re-scans the same query when the message-list instance changes', () {
    controller.search('alpha');
    expect(controller.hits.length, 3);

    // Transcript grows (live refresh / loadOlder assigns a new list instance);
    // the same query text must re-scan rather than keep stale hits.
    messages = _messages([
      'Plan the alpha feature.',
      'Let me grep for alpha in config.',
      'Alpha is now implemented.',
      'Also fix the beta bug.',
      'Alpha was shipped to production.',
    ]);
    controller.search('alpha');

    expect(controller.hits.length, 4);
    expect(controller.hits.last.messageId, 'm-4');
    expect(controller.hits.last.messageIndex, 4);
  });

  test('re-scanning the same query over the same instance is a no-op', () {
    controller.search('alpha');
    final hits = controller.hits;
    controller.search('alpha');
    expect(identical(controller.hits, hits), isTrue);
  });

  test('snippet is bounded by the real match length and never throws', () {
    // A match that runs to the end of the doc text: the snippet bound must be
    // derived from the actual match extent so downstream slicing cannot
    // RangeError near the string end.
    messages = _messages(['final target']);
    controller.search('target');
    final hit = controller.hits.single;
    expect(hit.messageIndex, 0);
    expect(hit.snippet.toLowerCase(), contains('target'));
  });
}
