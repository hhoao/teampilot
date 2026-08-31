import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../models/team_config.dart';
import '../../../models/team_generation_settings.dart';
import 'team_generation_launch.dart';

/// Durable team-generation workflow phases. Active phases have explicit
/// monotonic ranks (see [teamGenerationActivePhaseRank]); `failed`,
/// `cancelled`, and `complete` sit outside the rank scale.
enum TeamGenerationPhase {
  created,
  probing,
  planning,
  validating,
  committing,
  launching,
  delivering,
  delivered,
  cleaning,
  complete,
  failed,
  cancelled;

  String get value => name;

  static TeamGenerationPhase decode(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    return TeamGenerationPhase.values.firstWhere(
      (phase) => phase.value == value,
      orElse: () => TeamGenerationPhase.created,
    );
  }
}

/// Ranks only the forward-active phases; terminal/failed phases return null.
int? teamGenerationActivePhaseRank(TeamGenerationPhase phase) => switch (phase) {
  TeamGenerationPhase.created => 0,
  TeamGenerationPhase.probing => 1,
  TeamGenerationPhase.planning => 2,
  TeamGenerationPhase.validating => 3,
  TeamGenerationPhase.committing => 4,
  TeamGenerationPhase.launching => 5,
  TeamGenerationPhase.delivering => 6,
  TeamGenerationPhase.delivered => 7,
  TeamGenerationPhase.cleaning => 8,
  TeamGenerationPhase.complete => 9,
  _ => null,
};

enum TeamGenerationReceiptState { reserved, succeeded, failed, unknown }

/// Per-effect WAL receipt persisted inside the job (never the token).
final class TeamGenerationReceipt {
  const TeamGenerationReceipt({
    required this.state,
    this.value = '',
    this.digest = '',
    this.updatedAt = 0,
  });

  factory TeamGenerationReceipt.fromJson(Map<String, Object?> json) {
    final stateRaw = json['state']?.toString().trim() ?? '';
    final state = TeamGenerationReceiptState.values.firstWhere(
      (state) => state.name == stateRaw,
      orElse: () => TeamGenerationReceiptState.unknown,
    );
    return TeamGenerationReceipt(
      state: state,
      value: (json['value'] as String? ?? '').trim(),
      digest: (json['digest'] as String? ?? '').trim(),
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  final TeamGenerationReceiptState state;
  final String value;
  final String digest;
  final int updatedAt;

  Map<String, Object?> toJson() => {
    'state': state.name,
    if (value.isNotEmpty) 'value': value,
    if (digest.isNotEmpty) 'digest': digest,
    if (updatedAt != 0) 'updatedAt': updatedAt,
  };
}

/// Structured, bounded error record; [code] drives UI remediation.
final class TeamGenerationJobError {
  const TeamGenerationJobError({
    required this.code,
    this.message = '',
  });

  factory TeamGenerationJobError.fromJson(Map<String, Object?> json) {
    return TeamGenerationJobError(
      code: (json['code'] as String? ?? '').trim(),
      message: (json['message'] as String? ?? '').trim(),
    );
  }

  final String code;
  final String message;

  Map<String, Object?> toJson() => {
    'code': code,
    if (message.isNotEmpty) 'message': message,
  };
}

/// Team name/id reserved before the first commit side effect.
final class TeamGenerationTeamReservation {
  const TeamGenerationTeamReservation({
    required this.teamId,
    required this.teamName,
    required this.workflowDigest,
  });

  factory TeamGenerationTeamReservation.fromJson(Map<String, Object?> json) {
    return TeamGenerationTeamReservation(
      teamId: (json['teamId'] as String? ?? '').trim(),
      teamName: (json['teamName'] as String? ?? '').trim(),
      workflowDigest: (json['workflowDigest'] as String? ?? '').trim(),
    );
  }

  final String teamId;
  final String teamName;

  /// First 8 hex chars of the workflow stable id used for the name suffix.
  final String workflowDigest;

  Map<String, Object?> toJson() => {
    'teamId': teamId,
    'teamName': teamName,
    'workflowDigest': workflowDigest,
  };
}

/// Staged catalog resource recorded by the generation stager.
final class TeamGenerationStagedResource {
  const TeamGenerationStagedResource({
    required this.kind,
    required this.refId,
    required this.stagedPath,
    this.digest = '',
    this.createdAt = 0,
  });

  factory TeamGenerationStagedResource.fromJson(Map<String, Object?> json) {
    return TeamGenerationStagedResource(
      kind: (json['kind'] as String? ?? '').trim(),
      refId: (json['refId'] as String? ?? '').trim(),
      stagedPath: (json['stagedPath'] as String? ?? '').trim(),
      digest: (json['digest'] as String? ?? '').trim(),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String kind;
  final String refId;
  final String stagedPath;
  final String digest;
  final int createdAt;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'refId': refId,
    if (stagedPath.isNotEmpty) 'stagedPath': stagedPath,
    if (digest.isNotEmpty) 'digest': digest,
    if (createdAt != 0) 'createdAt': createdAt,
  };
}

/// `prefix` plus the first 20 lowercase hex chars of SHA-256 over [value];
/// keeps generated IDs independent of unsafe workflow characters.
String teamGenerationStableId(String prefix, String value) {
  final digest = sha256.convert(utf8.encode(value.trim())).toString();
  return '$prefix${digest.substring(0, 20)}';
}

/// Generator identity frozen at workflow start (no credentials).
final class TeamGenerationJobGenerator {
  const TeamGenerationJobGenerator({
    required this.generatorPresetId,
    required this.settingsRevision,
    required this.teamModeValue,
    required this.nativeCliValue,
  });

  factory TeamGenerationJobGenerator.fromSettings(
    TeamGenerationSettingsSnapshot snapshot,
  ) {
    return TeamGenerationJobGenerator(
      generatorPresetId: '',
      settingsRevision: snapshot.revision,
      teamModeValue: snapshot.teamMode.value,
      nativeCliValue: snapshot.nativeCli.value,
    );
  }

  factory TeamGenerationJobGenerator.fromJson(Map<String, Object?> json) {
    return TeamGenerationJobGenerator(
      generatorPresetId: (json['generatorPresetId'] as String? ?? '').trim(),
      settingsRevision: (json['settingsRevision'] as String? ?? '').trim(),
      teamModeValue: (json['teamMode'] as String? ?? '').trim(),
      nativeCliValue: (json['nativeCli'] as String? ?? '').trim(),
    );
  }

  /// Resolved once from the AI feature setting during preflight; empty when
  /// the feature has no pinned preset (provenance only, never credentials).
  final String generatorPresetId;
  final String settingsRevision;
  final String teamModeValue;
  final String nativeCliValue;

  bool get isEmpty => settingsRevision.isEmpty && teamModeValue.isEmpty;

  Map<String, Object?> toJson() => {
    'generatorPresetId': generatorPresetId,
    'settingsRevision': settingsRevision,
    'teamMode': teamModeValue,
    'nativeCli': nativeCliValue,
  };
}

/// Durable write-ahead-log record for one generation workflow.
///
/// Sensitive active payloads (prompt, plan, probes, staged resources,
/// generator/pool snapshots) live only on non-complete jobs; `complete` jobs
/// are tombstones that retain IDs plus delivery/cleanup receipts.
final class TeamGenerationJob {
  static const int schemaVersion = 1;

  const TeamGenerationJob({
    required this.workspaceId,
    required this.workflowId,
    required this.builderSessionId,
    required this.destinationSessionId,
    required this.teamId,
    required this.originalPrompt,
    required this.generator,
    required this.settings,
    required this.launch,
    required this.phase,
    required this.resumePhase,
    required this.attempt,
    required this.probeSnapshotJson,
    required this.normalizedPlanJson,
    required this.planRevision,
    required this.validatedRevision,
    required this.validatedDestinationJson,
    required this.finalizeIdempotencyKey,
    required this.receipts,
    required this.stagedResources,
    required this.teamReservation,
    required this.error,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TeamGenerationJob.fromJson(Map<String, Object?> json) {
    final version = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > schemaVersion) {
      throw FormatException('unsupported job schemaVersion: $version');
    }
    final phase = TeamGenerationPhase.decode(json['phase']);

    Map<String, TeamGenerationReceipt> decodeReceipts() {
      final raw = json['receipts'];
      if (raw is! Map) return const {};
      return Map<String, TeamGenerationReceipt>.unmodifiable({
        for (final entry in raw.entries)
          if (entry.value is Map)
            '${entry.key}': TeamGenerationReceipt.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            ),
      });
    }

    List<TeamGenerationStagedResource> decodeStaged() {
      final raw = json['stagedResources'];
      if (raw is! List) return const [];
      return List<TeamGenerationStagedResource>.unmodifiable([
        for (final value in raw)
          if (value is Map)
            TeamGenerationStagedResource.fromJson(
              value.cast<String, Object?>(),
            ),
      ]);
    }

    Map<String, Object?>? decodeJson(String key) {
      final raw = json[key];
      if (raw is! Map) return null;
      return raw.cast<String, Object?>();
    }

    final base = TeamGenerationJob(
      workspaceId: json['workspaceId'] as String? ?? '',
      workflowId: json['workflowId'] as String? ?? '',
      builderSessionId: json['builderSessionId'] as String? ?? '',
      destinationSessionId: json['destinationSessionId'] as String? ?? '',
      teamId: json['teamId'] as String? ?? '',
      originalPrompt: phase == TeamGenerationPhase.complete
          ? ''
          : json['originalPrompt'] as String? ?? '',
      generator: json['generator'] is Map
          ? TeamGenerationJobGenerator.fromJson(
              (json['generator'] as Map).cast<String, Object?>(),
            )
          : const TeamGenerationJobGenerator(
              generatorPresetId: '',
              settingsRevision: '',
              teamModeValue: '',
              nativeCliValue: '',
            ),
      settings: json['settings'] is Map
          ? TeamGenerationSettingsSnapshot.fromJson(
              (json['settings'] as Map).cast<String, Object?>(),
            )
          : _tombstoneSettings,
      launch: json['launch'] is Map
          ? TeamGenerationLaunchSnapshot.fromJson(
              (json['launch'] as Map).cast<String, Object?>(),
            )
          : _tombstoneLaunch,
      phase: phase,
      resumePhase: TeamGenerationPhase.decode(json['resumePhase']),
      attempt: (json['attempt'] as num?)?.toInt() ?? 0,
      probeSnapshotJson: phase == TeamGenerationPhase.complete
          ? null
          : decodeJson('probeSnapshot'),
      normalizedPlanJson: phase == TeamGenerationPhase.complete
          ? null
          : decodeJson('normalizedPlan'),
      planRevision: phase == TeamGenerationPhase.complete
          ? ''
          : json['planRevision'] as String? ?? '',
      validatedRevision: json['validatedRevision'] as String? ?? '',
      validatedDestinationJson: phase == TeamGenerationPhase.complete
          ? null
          : decodeJson('validatedDestination'),
      finalizeIdempotencyKey: json['finalizeIdempotencyKey'] as String? ?? '',
      receipts: decodeReceipts(),
      stagedResources: phase == TeamGenerationPhase.complete
          ? const []
          : decodeStaged(),
      teamReservation: json['teamReservation'] is Map
          ? TeamGenerationTeamReservation.fromJson(
              (json['teamReservation'] as Map).cast<String, Object?>(),
            )
          : null,
      error: json['error'] is Map
          ? TeamGenerationJobError.fromJson(
              (json['error'] as Map).cast<String, Object?>(),
            )
          : null,
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
    if (phase != TeamGenerationPhase.complete &&
        (json['generator'] is! Map ||
            json['settings'] is! Map ||
            json['launch'] is! Map)) {
      throw FormatException('active job requires generator/settings/launch');
    }
    return base;
  }

  static final TeamGenerationSettingsSnapshot _tombstoneSettings =
      TeamGenerationSettingsSnapshot(
        revision: '',
        capturedAt: 0,
        teamMode: TeamMode.mixed,
        nativeCli: CliTool.claude,
        modelPool: const [],
      );

  static final TeamGenerationLaunchSnapshot _tombstoneLaunch =
      TeamGenerationLaunchSnapshot(
        projectFolderPath: '',
        workingDirectoryPath: '',
        launchSecurityPolicyValue: '',
        folderIds: const [],
        targetIds: const [],
        workspaceRevision: '',
        capturedAt: 0,
      );

  final String workspaceId;
  final String workflowId;
  final String builderSessionId;
  final String destinationSessionId;
  final String teamId;
  final String originalPrompt;
  final TeamGenerationJobGenerator generator;
  final TeamGenerationSettingsSnapshot settings;
  final TeamGenerationLaunchSnapshot launch;
  final TeamGenerationPhase phase;
  final TeamGenerationPhase resumePhase;
  final int attempt;
  final Map<String, Object?>? probeSnapshotJson;
  final Map<String, Object?>? normalizedPlanJson;
  final String planRevision;
  final String validatedRevision;
  final Map<String, Object?>? validatedDestinationJson;
  final String finalizeIdempotencyKey;
  final Map<String, TeamGenerationReceipt> receipts;
  final List<TeamGenerationStagedResource> stagedResources;
  final TeamGenerationTeamReservation? teamReservation;
  final TeamGenerationJobError? error;
  final int createdAt;
  final int updatedAt;

  bool get isTerminal =>
      phase == TeamGenerationPhase.complete ||
      phase == TeamGenerationPhase.cancelled;

  bool get isActive => !isTerminal && phase != TeamGenerationPhase.failed;

  GeneratedDestinationLaunch? get validatedDestination =>
      validatedDestinationJson == null
      ? null
      : GeneratedDestinationLaunch.fromJson(validatedDestinationJson!);

  Map<String, Object?> toJson() {
    final tombstone = phase == TeamGenerationPhase.complete;
    return {
      'schemaVersion': schemaVersion,
      'workspaceId': workspaceId,
      'workflowId': workflowId,
      if (builderSessionId.isNotEmpty) 'builderSessionId': builderSessionId,
      if (destinationSessionId.isNotEmpty)
        'destinationSessionId': destinationSessionId,
      if (teamId.isNotEmpty) 'teamId': teamId,
      if (teamReservation != null) 'teamReservation': teamReservation!.toJson(),
      if (!tombstone) 'originalPrompt': originalPrompt,
      if (!tombstone) 'generator': generator.toJson(),
      if (!tombstone) 'settings': settings.toJson(),
      if (!tombstone) 'launch': launch.toJson(),
      'phase': phase.value,
      if (resumePhase != TeamGenerationPhase.created)
        'resumePhase': resumePhase.value,
      if (attempt != 0) 'attempt': attempt,
      if (!tombstone && probeSnapshotJson != null)
        'probeSnapshot': probeSnapshotJson,
      if (!tombstone && normalizedPlanJson != null)
        'normalizedPlan': normalizedPlanJson,
      if (!tombstone && planRevision.isNotEmpty) 'planRevision': planRevision,
      if (validatedRevision.isNotEmpty) 'validatedRevision': validatedRevision,
      if (!tombstone && validatedDestinationJson != null)
        'validatedDestination': validatedDestinationJson,
      if (finalizeIdempotencyKey.isNotEmpty)
        'finalizeIdempotencyKey': finalizeIdempotencyKey,
      if (receipts.isNotEmpty)
        'receipts': {
          for (final entry in receipts.entries) entry.key: entry.value.toJson(),
        },
      if (!tombstone && stagedResources.isNotEmpty)
        'stagedResources': [
          for (final resource in stagedResources) resource.toJson(),
        ],
      if (error != null) 'error': error!.toJson(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  TeamGenerationJob copyWith({
    String? destinationSessionId,
    String? teamId,
    TeamGenerationPhase? phase,
    TeamGenerationPhase? resumePhase,
    int? attempt,
    Map<String, Object?>? probeSnapshotJson,
    Map<String, Object?>? normalizedPlanJson,
    String? planRevision,
    String? validatedRevision,
    Map<String, Object?>? validatedDestinationJson,
    String? finalizeIdempotencyKey,
    Map<String, TeamGenerationReceipt>? receipts,
    List<TeamGenerationStagedResource>? stagedResources,
    TeamGenerationTeamReservation? teamReservation,
    TeamGenerationJobError? error,
    bool clearError = false,
    int? updatedAt,
  }) {
    return TeamGenerationJob(
      workspaceId: workspaceId,
      workflowId: workflowId,
      builderSessionId: builderSessionId,
      destinationSessionId: destinationSessionId ?? this.destinationSessionId,
      teamId: teamId ?? this.teamId,
      originalPrompt: originalPrompt,
      generator: generator,
      settings: settings,
      launch: launch,
      phase: phase ?? this.phase,
      resumePhase: resumePhase ?? this.resumePhase,
      attempt: attempt ?? this.attempt,
      probeSnapshotJson: probeSnapshotJson ?? this.probeSnapshotJson,
      normalizedPlanJson: normalizedPlanJson ?? this.normalizedPlanJson,
      planRevision: planRevision ?? this.planRevision,
      validatedRevision: validatedRevision ?? this.validatedRevision,
      validatedDestinationJson:
          validatedDestinationJson ?? this.validatedDestinationJson,
      finalizeIdempotencyKey:
          finalizeIdempotencyKey ?? this.finalizeIdempotencyKey,
      receipts: receipts ?? this.receipts,
      stagedResources: stagedResources ?? this.stagedResources,
      teamReservation: teamReservation ?? this.teamReservation,
      error: clearError ? null : (error ?? this.error),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Clears validated plan state when a later probe/workspace change
  /// invalidates a previously validated revision.
  TeamGenerationJob clearValidation() => copyWith(
    validatedRevision: '',
    validatedDestinationJson: null,
  );
}
