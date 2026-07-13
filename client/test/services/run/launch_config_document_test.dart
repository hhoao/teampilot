import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_config_document.dart';

void main() {
  test('parses version, configurations, compounds', () {
    final doc = LaunchConfigDocument.fromJson({
      'version': 1,
      'configurations': [
        {
          'id': 'api',
          'name': 'API',
          'type': 'shellScript',
          'request': 'launch',
          'execute': 'scriptText',
          'scriptText': 'echo hi',
        },
      ],
      'compounds': [
        {
          'id': 'all',
          'name': 'All',
          'configurations': ['api'],
        },
      ],
    });
    expect(doc.version, 1);
    expect(doc.configurations.single.id, 'api');
    expect(doc.configurations.single.type, 'shellScript');
    expect(doc.configurations.single.extras['scriptText'], 'echo hi');
    expect(doc.compounds.single.configurationIds, ['api']);
  });

  test('fills missing id from name slug on normalize', () {
    final doc = LaunchConfigDocument.fromJson({
      'version': 1,
      'configurations': [
        {
          'name': 'API Dev',
          'type': 'shellScript',
          'execute': 'scriptText',
          'scriptText': 'true',
        },
      ],
    }).normalized();
    expect(doc.configurations.single.id, isNotEmpty);
  });
}
