import 'dart:convert';

import 'dispatcher.dart';

const eventTransportProtocolVersion = 1;
const eventTransportMaxLineBytes = 65536;
const eventTransportFamilyAgentPresence = 'agentPresence';
const eventTransportFamilySessionLifecycle = 'sessionLifecycle';

String encodeTransportLine(Map<String, Object?> object) =>
    '${jsonEncode(object)}\n';

Map<String, Object?>? tryDecodeTransportLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final map = <String, Object?>{
    for (final e in decoded.entries) e.key.toString(): e.value,
  };
  if (map['v'] != eventTransportProtocolVersion) return null;
  return map;
}

bool transportLineTooLong(List<int> bytes) =>
    bytes.length > eventTransportMaxLineBytes;

abstract interface class EventTransportFamilyCodec {
  String get family;
  Map<String, Object?> encode(DispatcherEvent event);
  DispatcherEvent? decode(Map<String, Object?> payload);
}
