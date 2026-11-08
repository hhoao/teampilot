import 'hlc.dart';

/// A single value with a last-writer-wins stamp.
///
/// Writes must pass a stamp from the node's [HlcClock]; merging two registers
/// keeps the one with the greater stamp. Equal stamps keep the local value,
/// which is deterministic because stamps include the node id.
final class LwwRegister<T> {
  const LwwRegister({required this.value, required this.stamp});

  final T value;
  final Hlc stamp;

  LwwRegister<T> set(T next, Hlc nextStamp) =>
      LwwRegister<T>(value: next, stamp: nextStamp);

  LwwRegister<T> merge(LwwRegister<T> other) =>
      other.stamp.compareTo(stamp) > 0 ? other : this;

  Map<String, Object?> toJson(Object? Function(T value) encode) => {
    'v': encode(value),
    't': stamp.toJson(),
  };

  static LwwRegister<T>? fromJson<T>(
    Object? json, {
    required T Function(Object? value) decode,
  }) {
    if (json is! Map) return null;
    final stamp = Hlc.fromJson(json['t']);
    if (stamp == null) return null;
    try {
      return LwwRegister<T>(value: decode(json['v']), stamp: stamp);
    } on Object {
      return null;
    }
  }
}
