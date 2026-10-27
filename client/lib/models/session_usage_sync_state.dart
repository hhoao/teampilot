import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

@immutable
final class UsageSyncState extends Equatable {
  const UsageSyncState({this.lastFullScanAtMs, this.lastSyncAtMs});

  final int? lastFullScanAtMs;
  final int? lastSyncAtMs;

  bool get hasBaseline => lastFullScanAtMs != null;

  UsageSyncState copyWith({
    int? lastFullScanAtMs,
    int? lastSyncAtMs,
  }) {
    return UsageSyncState(
      lastFullScanAtMs: lastFullScanAtMs ?? this.lastFullScanAtMs,
      lastSyncAtMs: lastSyncAtMs ?? this.lastSyncAtMs,
    );
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    if (lastFullScanAtMs != null) 'lastFullScanAtMs': lastFullScanAtMs,
    if (lastSyncAtMs != null) 'lastSyncAtMs': lastSyncAtMs,
  };

  factory UsageSyncState.fromJson(Map<String, Object?> json) {
    return UsageSyncState(
      lastFullScanAtMs: (json['lastFullScanAtMs'] as num?)?.toInt(),
      lastSyncAtMs: (json['lastSyncAtMs'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [lastFullScanAtMs, lastSyncAtMs];
}
