import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/run/launch_variable_expander.dart';

void main() {
  test('expands workspaceFolder and env', () {
    final out = LaunchVariableExpander.expand(
      r'${workspaceFolder}/bin:${env:HOME}',
      workspaceFolder: '/proj',
      env: {'HOME': '/home/u'},
    );
    expect(out, '/proj/bin:/home/u');
  });
}
