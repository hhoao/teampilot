import 'package:flutter/foundation.dart';

import 'launch_configuration.dart';

/// Lifecycle state for a workspace run session.
enum RunSessionStatus {
  starting,
  running,
  exited,
  failed,
}

/// Runtime state for one launched configuration.
@immutable
class RunSession {
  const RunSession({
    required this.id,
    required this.owned,
    required this.status,
    this.exitCode,
    this.errorMessage,
    this.compoundId,
  });

  final String id;
  final OwnedLaunchConfiguration owned;
  final RunSessionStatus status;
  final int? exitCode;
  final String? errorMessage;

  /// When non-null, this session was started as part of a compound launch.
  final String? compoundId;

  String get selectionKey => owned.selectionKey;

  RunSession copyWith({
    String? id,
    OwnedLaunchConfiguration? owned,
    RunSessionStatus? status,
    int? exitCode,
    bool clearExitCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? compoundId,
    bool clearCompoundId = false,
  }) {
    return RunSession(
      id: id ?? this.id,
      owned: owned ?? this.owned,
      status: status ?? this.status,
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      compoundId: clearCompoundId ? null : (compoundId ?? this.compoundId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunSession &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          owned == other.owned &&
          status == other.status &&
          exitCode == other.exitCode &&
          errorMessage == other.errorMessage &&
          compoundId == other.compoundId;

  @override
  int get hashCode =>
      Object.hash(id, owned, status, exitCode, errorMessage, compoundId);
}
