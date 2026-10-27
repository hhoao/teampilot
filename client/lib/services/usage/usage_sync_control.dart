import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

final class UsageSyncControl {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const UsageSyncCancelled();
  }
}

final class UsageSyncCancelled implements Exception {
  const UsageSyncCancelled();

  @override
  String toString() => 'Usage sync cancelled';
}

@immutable
final class UsageSyncProgress extends Equatable {
  const UsageSyncProgress({
    this.targetsTotal = 0,
    this.targetsDone = 0,
    this.sourcesDone = 0,
    this.inserted = 0,
    this.updated = 0,
    this.skipped = 0,
    this.errors = 0,
    this.currentSourceId,
    this.isCancelled = false,
  });

  final int targetsTotal;
  final int targetsDone;
  final int sourcesDone;
  final int inserted;
  final int updated;
  final int skipped;
  final int errors;
  final String? currentSourceId;
  final bool isCancelled;

  @override
  List<Object?> get props => [
    targetsTotal,
    targetsDone,
    sourcesDone,
    inserted,
    updated,
    skipped,
    errors,
    currentSourceId,
    isCancelled,
  ];
}
