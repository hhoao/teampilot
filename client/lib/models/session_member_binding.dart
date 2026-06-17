import 'package:flutter/foundation.dart';

@immutable
class SessionMemberBinding {
  const SessionMemberBinding({
    required this.rosterMemberId,
    required this.taskId,
    String? typeId,
    this.nativeSessionIds = const {},
  }) : typeId = typeId ?? rosterMemberId;

  factory SessionMemberBinding.fromJson(Map<String, Object?> json) {
    final instanceId = json['rosterMemberId'] as String? ?? '';
    final nativeRaw = json['nativeSessionIds'];
    final native = nativeRaw is Map
        ? {
            for (final e in nativeRaw.entries)
              if (e.value != null) '${e.key}': '${e.value}',
          }
        : const <String, String>{};
    return SessionMemberBinding(
      rosterMemberId: instanceId,
      taskId: json['taskId'] as String? ?? '',
      typeId: json['typeId'] as String? ?? instanceId,
      nativeSessionIds: native,
    );
  }

  /// The runtime instance id (pod). Named `rosterMemberId` for history.
  final String rosterMemberId;

  /// The member **type** this instance belongs to (the routing key).
  final String typeId;
  final String taskId;

  /// CLI-native resume ids keyed by [CliTool.value]. Empty for `clientPinned`
  /// CLIs (claude/flashskyai), where the native id equals [taskId]. Holds the
  /// pre-allocated cursor chat id and captured codex/opencode session ids. See
  /// `docs/session-resume-architecture.md`.
  final Map<String, String> nativeSessionIds;

  /// Returns this binding with [nativeId] recorded for [toolValue], or `this`
  /// unchanged when already equal.
  SessionMemberBinding withNativeSessionId(String toolValue, String nativeId) {
    final tool = toolValue.trim();
    final id = nativeId.trim();
    if (tool.isEmpty || id.isEmpty || nativeSessionIds[tool] == id) return this;
    return SessionMemberBinding(
      rosterMemberId: rosterMemberId,
      taskId: taskId,
      typeId: typeId,
      nativeSessionIds: {...nativeSessionIds, tool: id},
    );
  }

  Map<String, Object?> toJson() => {
        'rosterMemberId': rosterMemberId,
        if (typeId != rosterMemberId) 'typeId': typeId,
        'taskId': taskId,
        if (nativeSessionIds.isNotEmpty) 'nativeSessionIds': nativeSessionIds,
      };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberBinding &&
            runtimeType == other.runtimeType &&
            rosterMemberId == other.rosterMemberId &&
            typeId == other.typeId &&
            taskId == other.taskId &&
            mapEquals(nativeSessionIds, other.nativeSessionIds);
  }

  @override
  int get hashCode => Object.hash(
        rosterMemberId,
        typeId,
        taskId,
        Object.hashAll(
          nativeSessionIds.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );
}
