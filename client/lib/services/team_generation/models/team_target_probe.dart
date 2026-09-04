import '../../../models/workspace.dart';

/// Per-target probe status.
enum TeamTargetProbeStatus { available, unavailable, timeout, staleTarget }

/// One CLI fact probed on one target (version/path basename only).
final class TeamTargetCliProbe {
  const TeamTargetCliProbe({
    required this.cliValue,
    required this.available,
    this.version = '',
    this.executableBasename = '',
    this.diagnostic = '',
  });

  /// Bounded (≤2 KiB) diagnostic projection of [rawDiagnostic].
  static TeamTargetCliProbe bounded({
    required String cliValue,
    required bool available,
    String version = '',
    String executableBasename = '',
    String diagnostic = '',
  }) {
    final trimmed = diagnostic.trim();
    return TeamTargetCliProbe(
      cliValue: cliValue,
      available: available,
      version: version.trim(),
      executableBasename: executableBasename.trim(),
      diagnostic: trimmed.length <= 2048
          ? trimmed
          : trimmed.substring(0, 2048),
    );
  }

  factory TeamTargetCliProbe.fromJson(Map<String, Object?> json) {
    return TeamTargetCliProbe(
      cliValue: (json['cli'] as String? ?? '').trim(),
      available: json['available'] as bool? ?? false,
      version: _clip(json['version']),
      executableBasename: _clip(json['executableBasename']),
      diagnostic: _clip(json['diagnostic']),
    );
  }

  final String cliValue;
  final bool available;
  final String version;
  final String executableBasename;

  /// Bounded (≤2 KiB) diagnostic code; never raw environment output.
  final String diagnostic;

  Map<String, Object?> toJson() => {
    'cli': cliValue,
    'available': available,
    if (version.isNotEmpty) 'version': version,
    if (executableBasename.isNotEmpty) 'executableBasename': executableBasename,
    if (diagnostic.isNotEmpty) 'diagnostic': diagnostic,
  };
}

/// One canonical target with its probed CLI facts.
final class TeamTargetProbe {
  const TeamTargetProbe({
    required this.targetId,
    required this.status,
    required this.folderIds,
    required this.cliProbes,
    this.transportKind = '',
    this.os = '',
    this.arch = '',
    this.cpuCount = 0,
    this.capturedAt = 0,
  });

  factory TeamTargetProbe.fromJson(Map<String, Object?> json) {
    return TeamTargetProbe(
      targetId: (json['targetId'] as String? ?? '').trim(),
      status: TeamTargetProbeStatus.values.firstWhere(
        (status) => status.name == (json['status'] as String? ?? ''),
        orElse: () => TeamTargetProbeStatus.unavailable,
      ),
      folderIds: [
        for (final value in (json['folderIds'] as List? ?? const []))
          if (value is String) value,
      ],
      cliProbes: [
        for (final value in (json['cliProbes'] as List? ?? const []))
          if (value is Map)
            TeamTargetCliProbe.fromJson(value.cast<String, Object?>()),
      ],
      transportKind: (json['transportKind'] as String? ?? '').trim(),
      os: _clip(json['os']),
      arch: _clip(json['arch']),
      cpuCount: (json['cpuCount'] as num?)?.toInt() ?? 0,
      capturedAt: (json['capturedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String targetId;
  final TeamTargetProbeStatus status;
  final List<String> folderIds;
  final List<TeamTargetCliProbe> cliProbes;
  final String transportKind;

  /// Redacted OS family / architecture labels (no hostnames, no usernames).
  final String os;
  final String arch;
  final int cpuCount;
  final int capturedAt;

  TeamTargetCliProbe? probeFor(String cliValue) {
    for (final probe in cliProbes) {
      if (probe.cliValue == cliValue) return probe;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'targetId': targetId,
    'status': status.name,
    'folderIds': folderIds,
    'cliProbes': [for (final probe in cliProbes) probe.toJson()],
    if (transportKind.isNotEmpty) 'transportKind': transportKind,
    if (os.isNotEmpty) 'os': os,
    if (arch.isNotEmpty) 'arch': arch,
    if (cpuCount != 0) 'cpuCount': cpuCount,
    'capturedAt': capturedAt,
  };
}

/// Canonical redacted snapshot persisted in the workflow job.
final class TeamTargetProbeSnapshot {
  const TeamTargetProbeSnapshot({
    required this.capturedAt,
    required this.targets,
    this.truncated = false,
  });

  factory TeamTargetProbeSnapshot.fromJson(Map<String, Object?> json) {
    return TeamTargetProbeSnapshot(
      capturedAt: (json['capturedAt'] as num?)?.toInt() ?? 0,
      targets: [
        for (final value in (json['targets'] as List? ?? const []))
          if (value is Map) TeamTargetProbe.fromJson(value.cast<String, Object?>()),
      ],
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final int capturedAt;
  final List<TeamTargetProbe> targets;
  final bool truncated;

  TeamTargetProbe? byTarget(String targetId) {
    for (final target in targets) {
      if (target.targetId == targetId) return target;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'capturedAt': capturedAt,
    'targets': [for (final target in targets) target.toJson()],
    if (truncated) 'truncated': truncated,
  };
}

/// One runner invocation; production uses the existing readiness commands.
abstract interface class TeamTargetProbeRunner {
  /// Returns bounded stdout facts for one target; must never install,
  /// upgrade, write files, or run shell redirections.
  Future<TeamTargetProbe> probe({
    required Workspace workspace,
    required String targetId,
    required Set<String> cliValues,
  });
}

/// Diagnostic fields are hard-capped at 2 KiB.
String clipDiagnostic(String value) {
  final trimmed = value.trim();
  return trimmed.length <= 2048 ? trimmed : trimmed.substring(0, 2048);
}

String _clip(Object? raw) => clipDiagnostic(raw?.toString() ?? '');
