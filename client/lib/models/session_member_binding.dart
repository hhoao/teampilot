import 'package:flutter/foundation.dart';

@immutable
class SessionMemberBinding {
  const SessionMemberBinding({
    required this.rosterMemberId,
    required this.taskId,
  });

  factory SessionMemberBinding.fromJson(Map<String, Object?> json) {
    return SessionMemberBinding(
      rosterMemberId: json['rosterMemberId'] as String? ?? '',
      taskId: json['taskId'] as String? ?? '',
    );
  }

  final String rosterMemberId;
  final String taskId;

  Map<String, Object?> toJson() => {
    'rosterMemberId': rosterMemberId,
    'taskId': taskId,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberBinding &&
            runtimeType == other.runtimeType &&
            rosterMemberId == other.rosterMemberId &&
            taskId == other.taskId;
  }

  @override
  int get hashCode => Object.hash(rosterMemberId, taskId);
}
