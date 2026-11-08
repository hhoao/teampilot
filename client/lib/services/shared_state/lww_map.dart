import 'hlc.dart';
import 'lww_register.dart';

/// A key/value map where each key is an independent LWW register.
///
/// Merging never drops a key: a key present on only one side is kept. A key
/// present on both sides takes the register with the greater stamp. This is
/// the right shape for display prefs: two devices editing different keys both
/// survive.
final class LwwMap<T> {
  const LwwMap({this.registers = const {}});

  final Map<String, LwwRegister<T>> registers;

  T? operator [](String key) => registers[key]?.value;

  Iterable<String> get keys => registers.keys;

  LwwMap<T> set(String key, T value, Hlc stamp) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return this;
    return LwwMap<T>(
      registers: {
        ...registers,
        trimmed: LwwRegister<T>(value: value, stamp: stamp),
      },
    );
  }

  LwwMap<T> merge(LwwMap<T> other) {
    final merged = <String, LwwRegister<T>>{...registers};
    for (final entry in other.registers.entries) {
      final local = merged[entry.key];
      merged[entry.key] = local == null
          ? entry.value
          : local.merge(entry.value);
    }
    return LwwMap<T>(registers: merged);
  }

  Map<String, Object?> toJson(Object? Function(T value) encode) => {
    'values': {
      for (final entry in registers.entries)
        entry.key: entry.value.toJson(encode),
    },
  };

  static LwwMap<T> fromJson<T>(
    Object? json, {
    required T Function(Object? value) decode,
  }) {
    if (json is! Map) return LwwMap<T>();
    final raw = json['values'];
    if (raw is! Map) return LwwMap<T>();
    final registers = <String, LwwRegister<T>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      final register = LwwRegister.fromJson<T>(entry.value, decode: decode);
      if (register != null) registers[key] = register;
    }
    return LwwMap<T>(registers: registers);
  }
}
