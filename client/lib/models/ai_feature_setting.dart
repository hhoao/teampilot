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
    required this.cli,
    required this.providerId,
    required this.model,
    this.effort = '',
  });

  final CliTool cli;
  final String providerId;
  final String model;

  /// Empty = use the capability default.
  final String effort;

  factory AiFeatureSetting.fromJson(Map<String, Object?> json) {
    return AiFeatureSetting(
      cli: CliTool.parse(json['cli'], fallback: CliTool.claude),
      providerId: (json['providerId'] as String? ?? '').trim(),
      model: (json['model'] as String? ?? '').trim(),
      effort: (json['effort'] as String? ?? '').trim(),
    );
  }

  Map<String, Object?> toJson() => {
    'cli': cli.value,
    'providerId': providerId,
    'model': model,
    'effort': effort,
  };

  AiFeatureSetting copyWith({
    CliTool? cli,
    String? providerId,
    String? model,
    String? effort,
  }) {
    return AiFeatureSetting(
      cli: cli ?? this.cli,
      providerId: providerId ?? this.providerId,
      model: model ?? this.model,
      effort: effort ?? this.effort,
    );
  }
}
