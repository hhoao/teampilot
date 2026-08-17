import 'package:flutter/foundation.dart';

import 'launch_security_policy.dart';

@immutable
class SessionMemberContinueOverride {
  const SessionMemberContinueOverride({
    this.presetId,
    this.provider,
    this.model,
    this.effort,
    this.launchSecurityPolicy,
  });

  factory SessionMemberContinueOverride.fromJson(Map<String, Object?> json) {
    return SessionMemberContinueOverride(
      presetId: _optionalString(json['presetId']),
      provider: _optionalString(json['provider']),
      model: _optionalString(json['model']),
      effort: _optionalString(json['effort']),
      launchSecurityPolicy: json.containsKey('launchSecurityPolicy')
          ? LaunchSecurityPolicyOverride.fromJson(json['launchSecurityPolicy'])
          : null,
    );
  }

  final String? presetId;
  final String? provider;
  final String? model;
  final String? effort;

  /// Partial policy; `cliDefault` dimensions remain inherited on merge.
  final LaunchSecurityPolicyOverride? launchSecurityPolicy;

  static const Object _unset = Object();

  SessionMemberContinueOverride copyWith({
    Object? presetId = _unset,
    Object? provider = _unset,
    Object? model = _unset,
    Object? effort = _unset,
    Object? launchSecurityPolicy = _unset,
  }) {
    return SessionMemberContinueOverride(
      presetId: presetId == _unset ? this.presetId : presetId as String?,
      provider: provider == _unset ? this.provider : provider as String?,
      model: model == _unset ? this.model : model as String?,
      effort: effort == _unset ? this.effort : effort as String?,
      launchSecurityPolicy: launchSecurityPolicy == _unset
          ? this.launchSecurityPolicy
          : launchSecurityPolicy as LaunchSecurityPolicyOverride?,
    );
  }

  Map<String, Object?> toJson() => {
    if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
    if (provider != null && provider!.isNotEmpty) 'provider': provider,
    if (model != null && model!.isNotEmpty) 'model': model,
    if (effort != null && effort!.isNotEmpty) 'effort': effort,
    if (launchSecurityPolicy != null)
      'launchSecurityPolicy': launchSecurityPolicy!.toJson(),
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
            launchSecurityPolicy == other.launchSecurityPolicy;
  }

  @override
  int get hashCode =>
      Object.hash(presetId, provider, model, effort, launchSecurityPolicy);
}

@immutable
class SessionContinueOverrides {
  const SessionContinueOverrides({
    this.launchSecurityPolicy,
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
      launchSecurityPolicy: json.containsKey('launchSecurityPolicy')
          ? LaunchSecurityPolicyOverride.fromJson(json['launchSecurityPolicy'])
          : null,
      memberOverrides: members,
    );
  }

  /// Partial policy; `cliDefault` dimensions remain inherited on merge.
  final LaunchSecurityPolicyOverride? launchSecurityPolicy;
  final Map<String, SessionMemberContinueOverride> memberOverrides;

  static const Object _unset = Object();

  SessionContinueOverrides copyWith({
    Object? launchSecurityPolicy = _unset,
    Map<String, SessionMemberContinueOverride>? memberOverrides,
  }) {
    return SessionContinueOverrides(
      launchSecurityPolicy: launchSecurityPolicy == _unset
          ? this.launchSecurityPolicy
          : launchSecurityPolicy as LaunchSecurityPolicyOverride?,
      memberOverrides: memberOverrides ?? this.memberOverrides,
    );
  }

  Map<String, Object?> toJson() => {
    if (launchSecurityPolicy != null)
      'launchSecurityPolicy': launchSecurityPolicy!.toJson(),
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
            launchSecurityPolicy == other.launchSecurityPolicy &&
            mapEquals(memberOverrides, other.memberOverrides);
  }

  @override
  int get hashCode => Object.hash(
    launchSecurityPolicy,
    Object.hashAll(
      memberOverrides.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
