import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import '../../support/in_memory_filesystem.dart';

void main() {
  const seat = RuntimeSeatKey(sessionId: 'session', memberId: 'member');

  test('file store preserves records across reopening', () async {
    final fs = InMemoryFilesystem();
    final first = FilePromptDeliveryStore(root: '/runtime/deliveries', fs: fs);
    final delivery = PromptDelivery(
      id: 'd1',
      seat: seat,
      cli: CliTool.codex,
      text: '  hello\nworld ',
      normalizedText: 'hello world',
      promptEpoch: 3,
      state: PromptDeliveryState.staged,
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25, 1),
    );

    await first.save(delivery);
    final reopened = FilePromptDeliveryStore(
      root: '/runtime/deliveries',
      fs: fs,
    );

    final read = await reopened.read('d1');
    expect(read?.text, '  hello\nworld ');
    expect(read?.normalizedText, 'hello world');
    expect(read?.promptEpoch, 3);
    expect((await reopened.activeFor(seat)).single.id, 'd1');
  });

  test('file store partitions deliveries by sessionId directory', () async {
    final fs = InMemoryFilesystem();
    const seatB = RuntimeSeatKey(sessionId: 'session', memberId: 'b');
    const otherSeat = RuntimeSeatKey(sessionId: 'other', memberId: 'member');
    final store = FilePromptDeliveryStore(root: '/runtime/deliveries', fs: fs);

    await store.save(_delivery('d1', seat, PromptDeliveryState.staged));
    await store.save(_delivery('d2', seatB, PromptDeliveryState.created));
    await store.save(_delivery('d3', otherSeat, PromptDeliveryState.created));

    // Seats are isolated to their own session directory (not a flat root).
    final rootEntries = await fs.listDir('/runtime/deliveries');
    expect(rootEntries, hasLength(2));
    expect(rootEntries.where((e) => !e.isDirectory), isEmpty);

    final sessionDir = '/runtime/deliveries/${_seg('session')}';
    final sessionEntries = await fs.listDir(sessionDir);
    expect(sessionEntries.map((e) => e.name).toSet(), {'d1.json', 'd2.json'});
    expect(
      await fs.listDir('/runtime/deliveries/${_seg('other')}').then(
        (entries) => entries.map((e) => e.name),
      ),
      ['d3.json'],
    );

    // Recovery surfaces only the requested session's seats.
    expect(await store.seatsForSession('session'), {seat, seatB});
    expect(await store.seatsForSession('other'), {otherSeat});
    expect(await store.seatsForSession('missing'), isEmpty);

    // Cross-session read-by-id still resolves the right record.
    expect((await store.read('d3'))!.seat, otherSeat);
  });
}

String _seg(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');

PromptDelivery _delivery(
  String id,
  RuntimeSeatKey seat,
  PromptDeliveryState state,
) =>
    PromptDelivery(
      id: id,
      seat: seat,
      cli: CliTool.codex,
      text: 'msg $id',
      normalizedText: 'msg $id',
      promptEpoch: 1,
      state: state,
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25),
    );
