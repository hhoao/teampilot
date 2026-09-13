import 'package:flutter/foundation.dart';

@immutable
class SessionMemberContinueOverride {
  const SessionMemberContinueOverride({
    this.presetId,
    this.provider,
    this.model,
    this.effort,
  });

  factory SessionMemberContinueOverride.fromJson(Map<String, Object?> json) {
    return SessionMemberContinueOverride(
      presetId: _optionalString(json['presetId']),
      provider: _optionalString(json['provider']),
      model: _optionalString(json['model']),
      effort: _optionalString(json['effort']),
    );
  }

  final String? presetId;
  final String? provider;
  final String? model;
  final String? effort;

  static const Object _unset = Object();

  SessionMemberContinueOverride copyWith({
    Object? presetId = _unset,
    Object? provider = _unset,
    Object? model = _unset,
    Object? effort = _unset,
  }) {
    return SessionMemberContinueOverride(
      presetId: presetId == _unset ? this.presetId : presetId as String?,
      provider: provider == _unset ? this.provider : provider as String?,
      model: model == _unset ? this.model : model as String?,
      effort: effort == _unset ? this.effort : effort as String?,
    );
  }

  Map<String, Object?> toJson() => {
    if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
    if (provider != null && provider!.isNotEmpty) 'provider': provider,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (effort != null && effort!.isNotEmpty) 'effort': effort,
  };

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SessionMemberContinueOverride &&
            runtimeType == other.runtimeType &&
            presetId == other.presetId &&
            provider == other.provider &&
            model == other.model &&
            effort == other.effort;
  }

  @override
  int get hashCode => Object.hash(presetId, provider, model, effort);
}

@immutable
class SessionContinueOverrides {
  const SessionContinueOverrides({this.memberOverrides = const {}});

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
    return SessionContinueOverrides(memberOverrides: members);
  }

  final Map<String, SessionMemberContinueOverride> memberOverrides;

  SessionContinueOverrides copyWith({
    Map<String, SessionMemberContinueOverride>? memberOverrides,
  }) {
    return SessionContinueOverrides(
      memberOverrides: memberOverrides ?? this.memberOverrides,
    );
  }

  Map<String, Object?> toJson() => {
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
            mapEquals(memberOverrides, other.memberOverrides);
  }

  @override
  int get hashCode => Object.hashAll(
    memberOverrides.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
