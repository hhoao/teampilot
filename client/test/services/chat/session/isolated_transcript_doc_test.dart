import 'dart:convert';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/isolated_transcript_doc.dart';

/// Plain, sendable adapter: one text fragment → one user message.
final class _TextAdapter implements AiTranscriptAdapter {
  const _TextAdapter();

  @override
  String get id => 'text';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async => [
    for (final fragment in bundle.fragments)
      AiMessage(
        id: 'm-${fragment.name}',
        role: AiRole.user,
        parts: [AiTextPart(text: utf8.decode(fragment.bytes))],
      ),
  ];
}

final class _ThrowingAdapter implements AiTranscriptAdapter {
  const _ThrowingAdapter();

  @override
  String get id => 'throwing';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async {
    throw StateError('boom');
  }
}

AiTranscriptBundle _bundle(List<String> lines) => AiTranscriptBundle(
  adapterId: 'text',
  fragments: [
    for (var i = 0; i < lines.length; i++)
      AiTranscriptFragment(name: '$i', bytes: utf8.encode(lines[i])),
  ],
);

void main() {
  test('projects the transcript on the worker isolate', () async {
    final worker = IsolatedTranscriptDoc();
    addTearDown(worker.dispose);

    final doc = await worker.build(
      const _TextAdapter(),
      _bundle(['Hello World', 'second line']),
    );

    // Same projection as the local builder, computed off the UI isolate.
    expect(doc.text, contains('user: Hello World'));
    expect(doc.text, contains('user: second line'));
    expect(doc.messageStarts, hasLength(2));
    expect(doc.folded.length, doc.text.length);
    expect(doc.folded, contains('hello world'));
  });

  test('reuses the same worker across parses', () async {
    final worker = IsolatedTranscriptDoc();
    addTearDown(worker.dispose);

    final first = await worker.build(const _TextAdapter(), _bundle(['one']));
    final second = await worker.build(const _TextAdapter(), _bundle(['two']));

    expect(first.text, contains('one'));
    expect(second.text, contains('two'));
  });

  test('surfaces adapter failures as errors', () async {
    final worker = IsolatedTranscriptDoc();
    addTearDown(worker.dispose);

    await expectLater(
      worker.build(const _ThrowingAdapter(), _bundle(['x'])),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('boom')),
      ),
    );
  });

  test('starts a fresh worker after dispose', () async {
    final worker = IsolatedTranscriptDoc();
    addTearDown(worker.dispose);

    expect(
      (await worker.build(const _TextAdapter(), _bundle(['before']))).text,
      contains('before'),
    );
    worker.dispose();
    expect(
      (await worker.build(const _TextAdapter(), _bundle(['after']))).text,
      contains('after'),
    );
  });
}
