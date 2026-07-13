import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/run/launch_configuration.dart';
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

  test('expandConfiguration expands shellScript extras string fields', () {
    final expanded = LaunchVariableExpander.expandConfiguration(
      const LaunchConfiguration(
        id: 'smoke',
        name: 'Smoke',
        type: 'shellScript',
        cwd: r'${workspaceFolder}',
        env: {'OUT': r'${workspaceFolder}/out'},
        extras: {
          'execute': 'scriptFile',
          'scriptPath': r'${workspaceFolder}/scripts/smoke.sh',
          'scriptText': r'echo ${workspaceFolder}',
          'interpreterPath': r'${workspaceFolder}/bin/bash',
          'interpreterOptions': r'--rc ${workspaceFolder}/rc',
          'scriptOptions': r'--root ${workspaceFolder}',
        },
      ),
      workspaceFolder: '/proj',
    );

    expect(expanded.cwd, '/proj');
    expect(expanded.env['OUT'], '/proj/out');
    expect(expanded.extras['scriptPath'], '/proj/scripts/smoke.sh');
    expect(expanded.extras['scriptText'], 'echo /proj');
    expect(expanded.extras['interpreterPath'], '/proj/bin/bash');
    expect(expanded.extras['interpreterOptions'], '--rc /proj/rc');
    expect(expanded.extras['scriptOptions'], '--root /proj');
    expect(expanded.extras['execute'], 'scriptFile');
  });
}
