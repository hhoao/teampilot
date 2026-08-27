import 'dart:convert';

import '../../models/team_config.dart';
import '../agent_runtime/runtime_event.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import 'prompt_delivery.dart';

abstract interface class PromptDeliveryStore {
  /// Makes [delivery] recoverable before the corresponding terminal effect.
  Future<void> save(PromptDelivery delivery);

  Future<PromptDelivery?> read(String id);

  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat);

  /// Includes terminal records for recovery history and diagnostics.
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat);

  /// Seats with at least one durable record in [sessionId]. Recovery uses
  /// this to open/replay every seat of a session without knowing its roster.
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId);
}

final class MemoryPromptDeliveryStore implements PromptDeliveryStore {
  final Map<String, PromptDelivery> _deliveries = {};

  @override
  Future<void> save(PromptDelivery delivery) async {
    _deliveries[delivery.id] = delivery;
  }

  @override
  Future<PromptDelivery?> read(String id) async => _deliveries[id];

  @override
  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) async =>
      (await forSeat(seat))
          .where((delivery) => !delivery.state.isTerminal)
          .toList(growable: false);

  @override
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat) async {
    final values = _deliveries.values
        .where((delivery) => delivery.seat == seat)
        .toList(growable: false);
    values.sort((left, right) => left.promptEpoch.compareTo(right.promptEpoch));
    return values;
  }

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) async => {
    for (final delivery in _deliveries.values)
      if (delivery.seat.sessionId == sessionId) delivery.seat,
  };
}

/// One JSON record per delivery, partitioned per session under
/// `root/{sessionId}/{id}.json`. Recovery scans only the requested session's
/// directory instead of a flat root. Atomic replacement means an observed
/// state transition always survives process restart as a complete record.
final class FilePromptDeliveryStore implements PromptDeliveryStore {
  FilePromptDeliveryStore({required this.root, Filesystem? fs})
    : _fs = fs ?? LocalFilesystem();

  final String root;
  final Filesystem _fs;

  String _sessionDirFor(RuntimeSeatKey seat) =>
      _fs.pathContext.join(root, _pathSegment(seat.sessionId));

  String _fileFor(PromptDelivery delivery) => _fs.pathContext.join(
    _sessionDirFor(delivery.seat),
    '${delivery.id}.json',
  );

  @override
  Future<void> save(PromptDelivery delivery) async {
    await _fs.ensureDir(_sessionDirFor(delivery.seat));
    await _fs.atomicWrite(_fileFor(delivery), jsonEncode(_encode(delivery)));
  }

  @override
  Future<PromptDelivery?> read(String id) async {
    final entries = await _fs.listDir(root);
    for (final entry in entries) {
      if (!entry.isDirectory) continue;
      final content = await _fs.readString(
        _fs.pathContext.join(root, entry.name, '$id.json'),
      );
      if (content == null || content.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(content);
        final delivery = decoded is Map
            ? _decode(Map<String, Object?>.from(decoded))
            : null;
        if (delivery != null && delivery.id == id) return delivery;
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  @override
  Future<List<PromptDelivery>> activeFor(RuntimeSeatKey seat) async =>
      (await forSeat(seat))
          .where((delivery) => !delivery.state.isTerminal)
          .toList(growable: false);

  @override
  Future<List<PromptDelivery>> forSeat(RuntimeSeatKey seat) async {
    final values = await _readDir(_sessionDirFor(seat));
    values.sort((left, right) => left.promptEpoch.compareTo(right.promptEpoch));
    return values
        .where((delivery) => delivery.seat == seat)
        .toList(growable: false);
  }

  @override
  Future<Set<RuntimeSeatKey>> seatsForSession(String sessionId) async => {
    for (final delivery in await _readDir(
      _fs.pathContext.join(root, _pathSegment(sessionId)),
    ))
      delivery.seat,
  };

  Future<List<PromptDelivery>> _readDir(String dir) async {
    final entries = await _fs.listDir(dir);
    final values = <PromptDelivery>[];
    for (final entry in entries) {
      if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
      final content = await _fs.readString(
        _fs.pathContext.join(dir, entry.name),
      );
      if (content == null) continue;
      try {
        final decoded = jsonDecode(content);
        final delivery = decoded is Map
            ? _decode(Map<String, Object?>.from(decoded))
            : null;
        if (delivery != null) values.add(delivery);
      } on FormatException {
        // An invalid record is never a valid active delivery.
      }
    }
    return values;
  }
}

Map<String, Object?> _encode(PromptDelivery delivery) => {
  'id': delivery.id,
  'sessionId': delivery.seat.sessionId,
  'memberId': delivery.seat.memberId,
  'cli': delivery.cli.name,
  'text': delivery.text,
  'normalizedText': delivery.normalizedText,
  'promptEpoch': delivery.promptEpoch,
  'state': delivery.state.name,
  'createdAt': delivery.createdAt.toUtc().toIso8601String(),
  'updatedAt': delivery.updatedAt.toUtc().toIso8601String(),
  'acceptsWeakConfirmation': delivery.acceptsWeakConfirmation,
  'failureReason': delivery.failureReason,
};

PromptDelivery? _decode(Map<String, Object?> value) {
  final id = value['id'] as String?;
  final sessionId = value['sessionId'] as String?;
  final memberId = value['memberId'] as String?;
  final cliName = value['cli'] as String?;
  final text = value['text'] as String?;
  final normalizedText = value['normalizedText'] as String?;
  final promptEpoch = (value['promptEpoch'] as num?)?.toInt();
  final stateName = value['state'] as String?;
  final createdAt = DateTime.tryParse(value['createdAt'] as String? ?? '');
  final updatedAt = DateTime.tryParse(value['updatedAt'] as String? ?? '');
  if (id == null ||
      sessionId == null ||
      memberId == null ||
      cliName == null ||
      text == null ||
      normalizedText == null ||
      promptEpoch == null ||
      stateName == null ||
      createdAt == null ||
      updatedAt == null) {
    return null;
  }
  final cli = _byName(CliTool.values, cliName);
  final state = _byName(PromptDeliveryState.values, stateName);
  if (cli == null || state == null) return null;
  return PromptDelivery(
    id: id,
    seat: RuntimeSeatKey(sessionId: sessionId, memberId: memberId),
    cli: cli,
    text: text,
    normalizedText: normalizedText,
    promptEpoch: promptEpoch,
    state: state,
    createdAt: createdAt,
    updatedAt: updatedAt,
    acceptsWeakConfirmation: value['acceptsWeakConfirmation'] as bool? ?? true,
    failureReason: value['failureReason'] as String?,
  );
}

T? _byName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Filesystem-safe path segment (base64url) so arbitrary session ids never
/// introduce nested or unsafe path separators.
String _pathSegment(String value) =>
    base64Url.encode(utf8.encode(value)).replaceAll('=', '');
