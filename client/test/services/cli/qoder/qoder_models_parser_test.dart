import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_models_service.dart';

void main() {
  test('parses account models and the current model id', () {
    final snapshot = parseQoderModelsResponse({
      'sessionId': 's1',
      'models': {
        'currentModelId': 'auto',
        'availableModels': [
          {'modelId': 'auto', 'name': 'Auto (default)'},
          {
            'modelId': 'smodel',
            'name': 'Sonus',
            'description': 'Reasoning · Vision · 8.00x Credit',
          },
          {'modelId': 'qwen3.8-max', 'name': 'Qwen3.8-Max'},
        ],
      },
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.modelIds, ['auto', 'smodel', 'qwen3.8-max']);
    expect(snapshot.defaultModelId, 'auto');
    expect(snapshot.names['smodel'], 'Sonus');
    expect(snapshot.names['qwen3.8-max'], 'Qwen3.8-Max');
    expect(
      snapshot.descriptions['smodel'],
      'Reasoning · Vision · 8.00x Credit',
    );
  });

  test('dedupes ids and drops blank entries', () {
    final snapshot = parseQoderModelsResponse({
      'models': {
        'availableModels': [
          {'modelId': 'auto'},
          {'modelId': 'auto'},
          {'modelId': '  '},
          {'name': 'no id'},
          'not-a-map',
        ],
      },
    });

    expect(snapshot!.modelIds, ['auto']);
  });

  test('returns null when the result carries no models', () {
    expect(parseQoderModelsResponse(null), isNull);
    expect(parseQoderModelsResponse({'sessionId': 's'}), isNull);
    expect(
      parseQoderModelsResponse({
        'models': {'availableModels': []},
      }),
      isNull,
    );
  });
}
