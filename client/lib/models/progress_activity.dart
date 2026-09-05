import 'package:equatable/equatable.dart';

import 'install_job/install_job_key.dart';

enum ProgressActivityKind {
  fileTreeImport,
  appUpdate,
  hubClone,
  packAcquire,
  cliProvision,
  repoClone,
}

enum ProgressActivityPhase {
  queued,
  running,
  cancelling,
  succeeded,
  failed,
  cancelled,
}

class ProgressActivity extends Equatable {
  const ProgressActivity({
    required this.id,
    required this.kind,
    required this.title,
    required this.phase,
    required this.createdAt,
    required this.updatedAt,
    this.subtitle,
    this.workspaceId,
    this.fraction,
    this.completedItems,
    this.totalItems,
    this.bytesDone,
    this.bytesTotal,
    this.cancellable = false,
    this.detailOpen = false,
    this.errorMessage,
    this.jobKey,
  });

  final String id;
  final ProgressActivityKind kind;
  final String title;
  final String? subtitle;

  /// Optional workspace scope. Null = app-global (e.g. appUpdate, hubClone).
  final String? workspaceId;
  final ProgressActivityPhase phase;
  final double? fraction;
  final int? completedItems;
  final int? totalItems;
  final int? bytesDone;
  final int? bytesTotal;
  final bool cancellable;
  final bool detailOpen;
  final String? errorMessage;
  final InstallJobKey? jobKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProgressActivity copyWith({
    String? id,
    ProgressActivityKind? kind,
    String? title,
    String? subtitle,
    String? workspaceId,
    ProgressActivityPhase? phase,
    double? fraction,
    int? completedItems,
    int? totalItems,
    int? bytesDone,
    int? bytesTotal,
    bool? cancellable,
    bool? detailOpen,
    String? errorMessage,
    InstallJobKey? jobKey,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProgressActivity(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      workspaceId: workspaceId ?? this.workspaceId,
      phase: phase ?? this.phase,
      fraction: fraction ?? this.fraction,
      completedItems: completedItems ?? this.completedItems,
      totalItems: totalItems ?? this.totalItems,
      bytesDone: bytesDone ?? this.bytesDone,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      cancellable: cancellable ?? this.cancellable,
      detailOpen: detailOpen ?? this.detailOpen,
      errorMessage: errorMessage ?? this.errorMessage,
      jobKey: jobKey ?? this.jobKey,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    kind,
    title,
    subtitle,
    workspaceId,
    phase,
    fraction,
    completedItems,
    totalItems,
    bytesDone,
    bytesTotal,
    cancellable,
    detailOpen,
    errorMessage,
    jobKey,
    createdAt,
    updatedAt,
  ];
}
