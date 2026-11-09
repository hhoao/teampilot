import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/codebuddy/provider/codebuddy_models_service.dart';

void main() {
  test('parses session/new models into ids, names and effort levels', () {
    final snapshot = parseCodebuddyModelsResponse(<String, Object?>{
      'sessionId': 's-1',
      'models': <String, Object?>{
        'currentModelId': 'hy3',
        'availableModels': <Object?>[
          <String, Object?>{
            'modelId': 'hy3',
            'name': 'Hy3',
            'description': 'x0.00 credits',
            '_meta': <String, Object?>{
              'effortOptions': <Object?>[
                <String, Object?>{'value': 'low', 'name': 'Low'},
                <String, Object?>{'value': 'high', 'name': 'High'},
              ],
            },
          },
          <String, Object?>{'modelId': 'glm-5.3', 'name': 'GLM-5.3'},
          <String, Object?>{
            'modelId': 'deepseek-v4-pro',
            'name': 'DeepSeek-V4-Pro',
            '_meta': <String, Object?>{'credits': 'x0.51 credits'},
          },
          <String, Object?>{'modelId': '   '},
          'junk',
        ],
      },
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.modelIds, ['hy3', 'glm-5.3', 'deepseek-v4-pro']);
    expect(snapshot.defaultModelId, 'hy3');
    expect(snapshot.names, {
      'hy3': 'Hy3',
      'glm-5.3': 'GLM-5.3',
      'deepseek-v4-pro': 'DeepSeek-V4-Pro',
    });
    expect(snapshot.effortOptions, {
      'hy3': ['low', 'high'],
    });
    expect(snapshot.descriptions, {
      'hy3': 'x0.00 credits',
      'deepseek-v4-pro': 'x0.51 credits',
    });
  });

  test('returns null when the result carries no models', () {
    expect(parseCodebuddyModelsResponse(null), isNull);
    expect(parseCodebuddyModelsResponse(<String, Object?>{}), isNull);
    expect(
      parseCodebuddyModelsResponse(<String, Object?>{
        'models': <String, Object?>{'availableModels': <Object?>[]},
      }),
      isNull,
    );
  });
}
