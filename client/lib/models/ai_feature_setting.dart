import 'team_config.dart';

/// AI features that have their own (CLI, provider, model, effort) config.
enum AiFeatureId {
  commitMessage('commitMessage'),
  teamGenerate('teamGenerate');

  const AiFeatureId(this.key);

  final String key;

  static AiFeatureId? tryParse(String? raw) {
    final v = raw?.trim();
    if (v == null || v.isEmpty) return null;
    for (final id in AiFeatureId.values) {
      if (id.key == v) return id;
    }
    return null;
  }
}

/// Which CLI provider/model/effort a single AI feature should use.
class AiFeatureSetting {
  const AiFeatureSetting({
    this.activePresetId,
    required this.cli,
    required this.providerId,
    required this.model,
    this.effort = '',
  });

  /// When set, [cli]/[providerId]/[model]/[effort] are resolved from this preset.
  final String? activePresetId;

  final CliTool cli;
  final String providerId;
  final String model;

  /// Empty = use the capability default.
  final String effort;

  factory AiFeatureSetting.fromJson(Map<String, Object?> json) {
    final presetRaw = (json['activePresetId'] as String? ?? '').trim();
    return AiFeatureSetting(
      activePresetId: presetRaw.isEmpty ? null : presetRaw,
      cli: CliTool.parse(json['cli'], fallback: CliTool.claude),
      providerId: (json['providerId'] as String? ?? '').trim(),
      model: (json['model'] as String? ?? '').trim(),
      effort: (json['effort'] as String? ?? '').trim(),
    );
  }

  Map<String, Object?> toJson() => {
    if (activePresetId != null) 'activePresetId': activePresetId,
    'cli': cli.value,
    'providerId': providerId,
    'model': model,
    'effort': effort,
  };

  AiFeatureSetting copyWith({
    String? activePresetId,
    bool clearActivePresetId = false,
    CliTool? cli,
    String? providerId,
    String? model,
    String? effort,
  }) {
    return AiFeatureSetting(
      activePresetId:
          clearActivePresetId ? null : (activePresetId ?? this.activePresetId),
      cli: cli ?? this.cli,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      effort: effort ?? this.effort,
    );
  }
}
