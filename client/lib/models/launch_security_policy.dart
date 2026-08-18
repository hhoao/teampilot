import 'package:flutter/foundation.dart';

enum LaunchApprovalPolicy { cliDefault, ask, autoApprove, never }

enum LaunchSandboxPolicy { cliDefault, readOnly, workspaceWrite, fullAccess }

enum LaunchHookTrustPolicy { cliDefault, trustedOnly, bypass }

/// Normalized, CLI-independent security intent for a launch.
@immutable
class LaunchSecurityPolicy {
  const LaunchSecurityPolicy({
    this.approval = LaunchApprovalPolicy.cliDefault,
    this.sandbox = LaunchSandboxPolicy.cliDefault,
    this.hookTrust = LaunchHookTrustPolicy.cliDefault,
  });

  /// Explicit full-access policy used by legacy full-access UI choices.
  static const fullAccess = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.never,
    sandbox: LaunchSandboxPolicy.fullAccess,
    hookTrust: LaunchHookTrustPolicy.bypass,
  );

  /// A cautious explicit preset for permission controls that need to show
  /// more than the CLI default/full-access pair.
  static const askReadOnlyTrusted = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.ask,
    sandbox: LaunchSandboxPolicy.readOnly,
    hookTrust: LaunchHookTrustPolicy.trustedOnly,
  );

  /// An explicit development preset that still retains trusted hook checks.
  static const autoApproveWorkspaceWriteTrusted = LaunchSecurityPolicy(
    approval: LaunchApprovalPolicy.autoApprove,
    sandbox: LaunchSandboxPolicy.workspaceWrite,
    hookTrust: LaunchHookTrustPolicy.trustedOnly,
  );

  factory LaunchSecurityPolicy.fromJson(Object? raw) {
    if (raw is! Map) return const LaunchSecurityPolicy();
    return LaunchSecurityPolicy(
      approval: _decodeEnum(
        LaunchApprovalPolicy.values,
        raw['approval'],
        LaunchApprovalPolicy.cliDefault,
      ),
      sandbox: _decodeEnum(
        LaunchSandboxPolicy.values,
        raw['sandbox'],
        LaunchSandboxPolicy.cliDefault,
      ),
      hookTrust: _decodeEnum(
        LaunchHookTrustPolicy.values,
        raw['hookTrust'],
        LaunchHookTrustPolicy.cliDefault,
      ),
    );
  }

  final LaunchApprovalPolicy approval;
  final LaunchSandboxPolicy sandbox;
  final LaunchHookTrustPolicy hookTrust;

  /// Whether this policy asks the launcher for an explicitly dangerous mode.
  bool get requiresDangerousExecution =>
      approval == LaunchApprovalPolicy.never &&
      sandbox == LaunchSandboxPolicy.fullAccess &&
      hookTrust == LaunchHookTrustPolicy.bypass;

  LaunchSecurityPolicy copyWith({
    LaunchApprovalPolicy? approval,
    LaunchSandboxPolicy? sandbox,
    LaunchHookTrustPolicy? hookTrust,
  }) {
    return LaunchSecurityPolicy(
      approval: approval ?? this.approval,
      sandbox: sandbox ?? this.sandbox,
      hookTrust: hookTrust ?? this.hookTrust,
    );
  }

  Map<String, Object?> toJson() => {
    'approval': approval.name,
    'sandbox': sandbox.name,
    'hookTrust': hookTrust.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchSecurityPolicy &&
          approval == other.approval &&
          sandbox == other.sandbox &&
          hookTrust == other.hookTrust;

  @override
  int get hashCode => Object.hash(approval, sandbox, hookTrust);
}

/// Nullable field-by-field override used by session continuation settings.
@immutable
class LaunchSecurityPolicyOverride {
  const LaunchSecurityPolicyOverride({
    this.approval,
    this.sandbox,
    this.hookTrust,
  });

  static const cliDefault = LaunchSecurityPolicyOverride(
    approval: LaunchApprovalPolicy.cliDefault,
    sandbox: LaunchSandboxPolicy.cliDefault,
    hookTrust: LaunchHookTrustPolicy.cliDefault,
  );

  static const fullAccess = LaunchSecurityPolicyOverride(
    approval: LaunchApprovalPolicy.never,
    sandbox: LaunchSandboxPolicy.fullAccess,
    hookTrust: LaunchHookTrustPolicy.bypass,
  );

  factory LaunchSecurityPolicyOverride.fromJson(Object? raw) {
    if (raw is! Map) return const LaunchSecurityPolicyOverride();
    return LaunchSecurityPolicyOverride(
      approval: _decodeNullableEnum(
        LaunchApprovalPolicy.values,
        raw['approval'],
      ),
      sandbox: _decodeNullableEnum(LaunchSandboxPolicy.values, raw['sandbox']),
      hookTrust: _decodeNullableEnum(
        LaunchHookTrustPolicy.values,
        raw['hookTrust'],
      ),
    );
  }

  factory LaunchSecurityPolicyOverride.fromPolicy(LaunchSecurityPolicy policy) {
    return LaunchSecurityPolicyOverride(
      approval: policy.approval,
      sandbox: policy.sandbox,
      hookTrust: policy.hookTrust,
    );
  }

  final LaunchApprovalPolicy? approval;
  final LaunchSandboxPolicy? sandbox;
  final LaunchHookTrustPolicy? hookTrust;

  static const Object _unset = Object();

  /// Updates selected dimensions while preserving omitted fields.
  ///
  /// Passing `null` explicitly clears a dimension; omitting it leaves the
  /// current override in place.
  LaunchSecurityPolicyOverride copyWith({
    Object? approval = _unset,
    Object? sandbox = _unset,
    Object? hookTrust = _unset,
  }) {
    return LaunchSecurityPolicyOverride(
      approval: approval == _unset
          ? this.approval
          : approval as LaunchApprovalPolicy?,
      sandbox: sandbox == _unset
          ? this.sandbox
          : sandbox as LaunchSandboxPolicy?,
      hookTrust: hookTrust == _unset
          ? this.hookTrust
          : hookTrust as LaunchHookTrustPolicy?,
    );
  }

  bool get requiresDangerousExecution =>
      approval == LaunchApprovalPolicy.never &&
      sandbox == LaunchSandboxPolicy.fullAccess &&
      hookTrust == LaunchHookTrustPolicy.bypass;

  LaunchSecurityPolicy applyTo(LaunchSecurityPolicy base) =>
      base.copyWith(approval: approval, sandbox: sandbox, hookTrust: hookTrust);

  Map<String, Object?> toJson() => {
    if (approval != null) 'approval': approval!.name,
    if (sandbox != null) 'sandbox': sandbox!.name,
    if (hookTrust != null) 'hookTrust': hookTrust!.name,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchSecurityPolicyOverride &&
          approval == other.approval &&
          sandbox == other.sandbox &&
          hookTrust == other.hookTrust;

  @override
  int get hashCode => Object.hash(approval, sandbox, hookTrust);
}

T _decodeEnum<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw?.toString().trim();
  if (name == null || name.isEmpty) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

T? _decodeNullableEnum<T extends Enum>(List<T> values, Object? raw) {
  final name = raw?.toString().trim();
  if (name == null || name.isEmpty) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}
