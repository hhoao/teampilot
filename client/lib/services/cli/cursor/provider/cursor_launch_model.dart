/// Maps TeamPilot picker ids (cursor-agent model slugs) to the native
/// `cli-config.json` `modelId` + parameters cursor-agent persists after a
/// successful catalog load.
///
/// Launch argv no longer passes `--model` (live-catalog races caused hard
/// exits). The stamped `cli-config.json` is the sole selection path.
final class CursorLaunchModel {
  const CursorLaunchModel({required this.modelId, required this.parameters});

  final String modelId;
  final List<Map<String, String>> parameters;

  static const _effortValues = <String>{
    'none',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  };

  static CursorLaunchModel? parse(String pickerId) {
    var id = pickerId.trim();
    if (id.isEmpty) return null;

    var peeledFast = false;
    if (id.endsWith('-fast')) {
      peeledFast = true;
      id = id.substring(0, id.length - '-fast'.length);
    }

    String? effort;
    for (final value in _effortValues) {
      final suffix = '-$value';
      if (id.endsWith(suffix)) {
        effort = value;
        id = id.substring(0, id.length - suffix.length);
        break;
      }
    }

    const cursorPrefix = 'cursor-';
    if (id.startsWith(cursorPrefix)) {
      id = id.substring(cursorPrefix.length);
    }

    final parameters = <Map<String, String>>[
      if (effort != null) {'id': 'effort', 'value': effort},
      if (effort != null || peeledFast)
        {'id': 'fast', 'value': peeledFast ? 'true' : 'false'},
    ];
    return CursorLaunchModel(modelId: id, parameters: parameters);
  }

  static Map<String, Object?> applyToConfig(
    Map<String, Object?> config,
    String pickerId,
  ) {
    final parsed = parse(pickerId);
    if (parsed == null) return config;

    final stamped = Map<String, Object?>.from(config);
    stamped['hasChangedDefaultModel'] = true;
    stamped['model'] = <String, Object?>{'modelId': parsed.modelId};
    // cursor-agent Zod requires `selectedModel.parameters` (array). Omitting
    // it makes FileBasedConfigProvider rename cli-config.json → .bad and
    // regenerate defaults (Auto). Always stamp parameters, even when empty.
    stamped['selectedModel'] = <String, Object?>{
      'modelId': parsed.modelId,
      'parameters': parsed.parameters,
    };
    if (parsed.parameters.isNotEmpty) {
      final modelParameters = Map<String, Object?>.from(
        (stamped['modelParameters'] as Map?)?.cast<String, Object?>() ??
            const {},
      );
      modelParameters[parsed.modelId] = parsed.parameters;
      stamped['modelParameters'] = modelParameters;
    }
    return stamped;
  }
}
