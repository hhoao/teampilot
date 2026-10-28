import 'dart:convert';

import '../../models/cursor_usage_range.dart';
import '../io/filesystem.dart';

/// Persists the last selected range as a single string.
final class CursorUsageRangePreference {
  CursorUsageRangePreference({required Filesystem fs, required String path})
    : _fs = fs,
      _path = path;

  final Filesystem _fs;
  final String _path;

  Future<CursorUsageRange> load() async {
    final raw = await _fs.readString(_path);
    if (raw == null || raw.trim().isEmpty) {
      return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
      }
      return decodeCursorUsageRange(Map<String, Object?>.from(decoded));
    } on Object {
      return const CursorUsagePresetRange(CursorUsagePreset.billingCycle);
    }
  }

  Future<void> save(CursorUsageRange range) async {
    await _fs.ensureDir(_fs.pathContext.dirname(_path));
    await _fs.atomicWrite(_path, jsonEncode(encodeCursorUsageRange(range)));
  }
}

Map<String, Object?> encodeCursorUsageRange(CursorUsageRange range) =>
    switch (range) {
      CursorUsagePresetRange(:final preset) => {'preset': preset.name},
      CursorUsageCustomRange(:final startMs, :final endMs) => {
        'startMs': startMs,
        'endMs': endMs,
      },
    };

CursorUsageRange decodeCursorUsageRange(Map<String, Object?> json) {
  final startMs = (json['startMs'] as num?)?.toInt();
  final endMs = (json['endMs'] as num?)?.toInt();
  if (startMs != null && endMs != null) {
    return CursorUsageCustomRange(startMs: startMs, endMs: endMs);
  }
  final preset = CursorUsagePreset.values.firstWhere(
    (value) => value.name == json['preset'],
    orElse: () => CursorUsagePreset.billingCycle,
  );
  return CursorUsagePresetRange(preset);
}
