import 'dart:math' as math;

/// Hybrid Logical Clock stamp: wall clock + logical counter + node id.
///
/// `(wallMillis, counter, nodeId)` is a total order. The node id is the final
/// tie-breaker so two devices that observe the same wall clock still converge
/// on one winner.
final class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.wallMillis,
    required this.counter,
    required this.nodeId,
  });

  static const zero = Hlc(wallMillis: 0, counter: 0, nodeId: '');

  final int wallMillis;
  final int counter;
  final String nodeId;

  bool get isZero => wallMillis == 0 && counter == 0 && nodeId.isEmpty;

  @override
  int compareTo(Hlc other) {
    final byWall = wallMillis.compareTo(other.wallMillis);
    if (byWall != 0) return byWall;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    return nodeId.compareTo(other.nodeId);
  }

  bool isAfter(Hlc other) => compareTo(other) > 0;

  Hlc max(Hlc other) => compareTo(other) >= 0 ? this : other;

  Map<String, Object?> toJson() => {'w': wallMillis, 'c': counter, 'n': nodeId};

  /// Accepts either the map form produced by [toJson] or a wire string
  /// produced by [toWire].
  static Hlc? fromJson(Object? value) {
    if (value is Hlc) return value;
    if (value is Map) {
      final wall = value['w'];
      final counter = value['c'];
      if (wall is num && counter is num) {
        final node = value['n'];
        return Hlc(
          wallMillis: wall.toInt(),
          counter: counter.toInt(),
          nodeId: node is String ? node : '',
        );
      }
      return null;
    }
    if (value is String) return parse(value);
    return null;
  }

  /// Parses `<wall>:<counter>:<nodeId>`. Node ids may contain `:`.
  static Hlc? parse(String? wire) {
    final text = wire?.trim() ?? '';
    if (text.isEmpty) return null;
    final parts = text.split(':');
    if (parts.length < 3) return null;
    final wall = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1]);
    if (wall == null || counter == null) return null;
    return Hlc(
      wallMillis: wall,
      counter: counter,
      nodeId: parts.sublist(2).join(':'),
    );
  }

  String toWire() => '$wallMillis:$counter:$nodeId';

  @override
  String toString() => toWire();
}

/// Generates monotonically increasing [Hlc] values for one node.
final class HlcClock {
  HlcClock({required this.nodeId, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String nodeId;
  final DateTime Function() _clock;

  Hlc _last = Hlc.zero;

  Hlc get current => _last;

  /// A fresh local event stamp, strictly greater than the previous one.
  Hlc now() {
    final wall = _clock().millisecondsSinceEpoch;
    final last = _last;
    final next = wall > last.wallMillis
        ? Hlc(wallMillis: wall, counter: 0, nodeId: nodeId)
        : Hlc(
            wallMillis: last.wallMillis,
            counter: last.counter + 1,
            nodeId: nodeId,
          );
    _last = next;
    return next;
  }

  /// Incorporate a remote stamp and return a local stamp strictly greater
  /// than both the previous local and the remote one.
  Hlc observe(Hlc remote) {
    final wall = math.max(
      _clock().millisecondsSinceEpoch,
      math.max(_last.wallMillis, remote.wallMillis),
    );
    final last = _last;
    final int counter;
    if (wall == last.wallMillis && wall == remote.wallMillis) {
      counter = math.max(last.counter, remote.counter) + 1;
    } else if (wall == last.wallMillis) {
      counter = last.counter + 1;
    } else if (wall == remote.wallMillis) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    final next = Hlc(wallMillis: wall, counter: counter, nodeId: nodeId);
    _last = next;
    return next;
  }
}
