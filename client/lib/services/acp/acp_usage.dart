/// One persisted ACP `usage_update` sample.
///
/// ACP reports `used` / `size` for the session's context window. Probe 1.4.3
/// (Antigravity) shows `used` is a per-turn context delta, not a cumulative
/// total and not output tokens, so a record only mirrors the raw sample and
/// never derives output/cost values.
final class AcpUsageRecord {
  const AcpUsageRecord({
    required this.sessionId,
    required this.used,
    required this.size,
    required this.sequence,
    this.model,
    this.cost,
  });

  /// Builds a record from one live update.
  ///
  /// [sequence] is a microsecond stamp (unique per append, also used as the
  /// event timestamp) unless the caller supplies a narrower value for tests.
  factory AcpUsageRecord.fromUpdate({
    required String sessionId,
    required int? used,
    required int? size,
    Object? cost,
    String? model,
    int? sequence,
  }) => AcpUsageRecord(
    sessionId: sessionId,
    used: used ?? 0,
    size: size ?? 0,
    sequence: sequence ?? DateTime.now().microsecondsSinceEpoch,
    model: (model == null || model.trim().isEmpty) ? null : model.trim(),
    cost: encodeUsageCost(cost),
  );

  factory AcpUsageRecord.fromJson(Map<String, Object?> json) => AcpUsageRecord(
    sessionId: '${json['sessionId'] ?? ''}',
    used: (json['used'] as num?)?.toInt() ?? 0,
    size: (json['size'] as num?)?.toInt() ?? 0,
    sequence: (json['sequence'] as num?)?.toInt() ?? 0,
    model: json['model']?.toString(),
    cost: json['cost'],
  );

  /// The ACP session id the sample belongs to.
  final String sessionId;

  /// Context tokens the agent reported in use for the turn.
  final int used;

  /// Agent context window size (the ACP `size` field).
  final int size;

  /// Microsecond stamp; also the request-id discriminator.
  final int sequence;

  /// Model the session was using when the sample arrived, when known.
  final String? model;

  /// Agent-reported cost payload (already JSON-safe), when present.
  final Object? cost;

  /// Probe 1.4.3: `used` is input/context tokens only.
  int get totalTokens => used;

  /// Wall-clock millis derived from [sequence].
  int get timestampMs => sequence ~/ 1000;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'used': used,
    'size': size,
    'sequence': sequence,
    if (model != null) 'model': model,
    if (cost != null) 'cost': cost,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpUsageRecord &&
          sessionId == other.sessionId &&
          used == other.used &&
          size == other.size &&
          sequence == other.sequence &&
          model == other.model &&
          _sameCost(cost, other.cost);

  @override
  int get hashCode =>
      Object.hash(sessionId, used, size, sequence, model, cost);

  static bool _sameCost(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
          return false;
        }
      }
      return true;
    }
    return a == b;
  }
}

/// Normalizes an ACP [`acpd.Cost`] (or a JSON map) into a JSON-safe value.
///
/// The record is appended with `jsonEncode`, so a typed cost object must be
/// converted here; anything unrecognizable is dropped rather than failing the
/// whole append.
Object? encodeUsageCost(Object? cost) {
  if (cost == null) return null;
  if (cost is num || cost is String || cost is bool) return cost;
  if (cost is Map) return Map<String, Object?>.from(cost);
  try {
    final dynamic typed = cost;
    final json = typed.toJson();
    if (json is Map) return Map<String, Object?>.from(json);
  } on Object {
    return null;
  }
  return null;
}
