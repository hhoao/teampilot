import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

enum CursorUsagePreset { billingCycle, today, sevenDays, thirtyDays, lastMonth }

sealed class CursorUsageRange extends Equatable {
  const CursorUsageRange();
}

final class CursorUsagePresetRange extends CursorUsageRange {
  const CursorUsagePresetRange(this.preset);

  final CursorUsagePreset preset;

  @override
  List<Object?> get props => [preset];
}

final class CursorUsageCustomRange extends CursorUsageRange {
  const CursorUsageCustomRange({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  @override
  List<Object?> get props => [startMs, endMs];
}

@immutable
final class CursorUsageWindow extends Equatable {
  const CursorUsageWindow({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;

  bool contains(int ms) => ms >= startMs && ms <= endMs;

  int get durationMs => endMs - startMs;

  @override
  List<Object?> get props => [startMs, endMs];
}
