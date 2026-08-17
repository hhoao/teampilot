import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/widgets/app_provider/provider_model_picker_field.dart';

void main() {
  const original = AppProviderConfig(
    id: 'openai',
    cli: CliTool.codex,
    name: 'OpenAI',
    apiKey: 'old-key',
    baseUrl: 'https://api.openai.com',
  );

  test('provider credentials and endpoint changes trigger catalog refresh', () {
    expect(
      providerModelPickerProviderChanged(
        original,
        original.copyWith(apiKey: 'new-key'),
      ),
      isTrue,
    );
    expect(
      providerModelPickerProviderChanged(
        original,
        original.copyWith(baseUrl: 'https://proxy.example.test'),
      ),
      isTrue,
    );
  });

  test('unchanged provider config does not trigger catalog refresh', () {
    expect(providerModelPickerProviderChanged(original, original), isFalse);
  });
}
