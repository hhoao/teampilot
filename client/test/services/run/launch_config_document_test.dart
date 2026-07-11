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
          'type': 'process',
          'request': 'launch',
          'command': 'echo',
          'args': ['hi'],
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
    expect(doc.compounds.single.configurationIds, ['api']);
  });

  test('fills missing id from name slug on normalize', () {
    final doc = LaunchConfigDocument.fromJson({
      'version': 1,
      'configurations': [
        {'name': 'API Dev', 'type': 'process', 'command': 'true'},
      ],
    }).normalized();
    expect(doc.configurations.single.id, isNotEmpty);
  });
}
