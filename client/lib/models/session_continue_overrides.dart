import 'package:flutter/foundation.dart';

@immutable
class SessionMemberContinueOverride {
  const SessionMemberContinueOverride({
    this.presetId,
    this.provider,
    this.model,
    this.effort,
    this.dangerouslySkipPermissions,
  });

  factory SessionMemberContinueOverride.fromJson(Map<String, Object?> json) {
    return SessionMemberContinueOverride(
      presetId: _optionalString(json['presetId']),
      provider: _optionalString(json['provider']),
      model: _optionalString(json['model']),
      effort: _optionalString(json['effort']),
      dangerouslySkipPermissions: json['dangerouslySkipPermissions'] as bool?,
    );
  }

  final String? presetId;
  final String? provider;
  final String? model;
  final String? effort;
  final bool? dangerouslySkipPermissions;

  SessionMemberContinueOverride copyWith({
    String? presetId,
    String? provider,
    String? model,
    String? effort,
    bool? dangerouslySkipPermissions,
  }) {
    return SessionMemberContinueOverride(
      presetId: presetId ?? this.presetId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      effort: effort ?? this.effort,
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
    );
  }

  Map<String, Object?> toJson() => {
    if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
    if (provider != null && provider!.isNotEmpty) 'provider': provider,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (effort != null && effort!.isNotEmpty) 'effort': effort,
    if (dangerouslySkipPermissions != null)
      'dangerouslySkipPermissions': dangerouslySkipPermissions,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberContinueOverride &&
            runtimeType == other.runtimeType &&
            presetId == other.presetId &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions;
  }

  @override
  int get hashCode => Object.hash(
    presetId,
    provider,
    model,
    effort,
    dangerouslySkipPermissions,
  );
}

@immutable
class SessionContinueOverrides {
  const SessionContinueOverrides({
    this.dangerouslySkipPermissions,
    this.memberOverrides = const {},
  });

  factory SessionContinueOverrides.fromJson(Map<String, Object?>? json) {
    if (json == null || json.isEmpty) {
      return const SessionContinueOverrides();
    }
    final membersRaw = json['memberOverrides'];
    final members = membersRaw is Map
        ? <String, SessionMemberContinueOverride>{
            for (final e in membersRaw.entries)
              if ('${e.key}'.trim().isNotEmpty && e.value is Map)
                '${e.key}'.trim(): SessionMemberContinueOverride.fromJson(
                  Map<String, Object?>.from(e.value as Map),
                ),
          }
        : const <String, SessionMemberContinueOverride>{};
    return SessionContinueOverrides(
      dangerouslySkipPermissions: json['dangerouslySkipPermissions'] as bool?,
      memberOverrides: members,
    );
  }

  final bool? dangerouslySkipPermissions;
  final Map<String, SessionMemberContinueOverride> memberOverrides;

  SessionContinueOverrides copyWith({
    bool? dangerouslySkipPermissions,
    Map<String, SessionMemberContinueOverride>? memberOverrides,
  }) {
    return SessionContinueOverrides(
      dangerouslySkipPermissions:
          dangerouslySkipPermissions ?? this.dangerouslySkipPermissions,
      memberOverrides: memberOverrides ?? this.memberOverrides,
    );
  }

  Map<String, Object?> toJson() => {
    if (dangerouslySkipPermissions != null)
      'dangerouslySkipPermissions': dangerouslySkipPermissions,
    if (memberOverrides.isNotEmpty)
      'memberOverrides': {
        for (final e in memberOverrides.entries) e.key: e.value.toJson(),
      },
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionContinueOverrides &&
            runtimeType == other.runtimeType &&
            dangerouslySkipPermissions == other.dangerouslySkipPermissions &&
            mapEquals(memberOverrides, other.memberOverrides);
  }

  @override
  int get hashCode => Object.hash(
    dangerouslySkipPermissions,
    Object.hashAll(
      memberOverrides.entries.map(
        (e) => Object.hash(e.key, e.value),
      ),
    ),
  );
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
