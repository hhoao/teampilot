import 'package:flutter/foundation.dart';

@immutable
class SessionMemberBinding {
  const SessionMemberBinding({
    required this.rosterMemberId,
    required this.taskId,
    String? typeId,
  }) : typeId = typeId ?? rosterMemberId;

  factory SessionMemberBinding.fromJson(Map<String, Object?> json) {
    final instanceId = json['rosterMemberId'] as String? ?? '';
    return SessionMemberBinding(
      rosterMemberId: instanceId,
      taskId: json['taskId'] as String? ?? '',
      typeId: json['typeId'] as String? ?? instanceId,
    );
  }

  /// The runtime instance id (pod). Named `rosterMemberId` for history.
  final String rosterMemberId;

  /// The member **type** this instance belongs to (the routing key).
  final String typeId;
  final String taskId;

  Map<String, Object?> toJson() => {
        'rosterMemberId': rosterMemberId,
        if (typeId != rosterMemberId) 'typeId': typeId,
        'taskId': taskId,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberBinding &&
            runtimeType == other.runtimeType &&
            rosterMemberId == other.rosterMemberId &&
            typeId == other.typeId &&
            taskId == other.taskId;
  }

  @override
  int get hashCode => Object.hash(rosterMemberId, typeId, taskId);
}
