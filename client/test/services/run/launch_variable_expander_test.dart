import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  test('expandPath re-spells Windows backslashes into posix style', () {
    expect(
      LaunchVariableExpander.expandPath(
        r'${workspaceFolder}\client',
        workspaceFolder: '/proj',
        style: p.Style.posix,
      ),
      '/proj/client',
    );
  });

  test('expandPath re-spells posix slashes into windows style', () {
    expect(
      LaunchVariableExpander.expandPath(
        r'${workspaceFolder}/client',
        workspaceFolder: r'C:\proj',
        style: p.Style.windows,
      ),
      r'C:\proj\client',
    );
  });

  test(
    'expandConfiguration normalizes cwd and scriptPath to the target style',
    () {
      final expanded = LaunchVariableExpander.expandConfiguration(
        const LaunchConfiguration(
          id: 'sh',
          name: 'Shell',
          type: 'shellScript',
          cwd: r'${workspaceFolder}\client',
          extras: {
            'execute': 'scriptFile',
            'scriptPath': r'${workspaceFolder}\scripts\run.sh',
          },
        ),
        workspaceFolder: '/proj',
        pathStyle: p.Style.posix,
      );

      expect(expanded.cwd, '/proj/client');
      expect(expanded.extras['scriptPath'], '/proj/scripts/run.sh');
    },
  );

  test(
    'expandConfiguration leaves interpreterPath and script text verbatim',
    () {
      final expanded = LaunchVariableExpander.expandConfiguration(
        const LaunchConfiguration(
          id: 'sh',
          name: 'Shell',
          type: 'shellScript',
          extras: {
            'execute': 'scriptText',
            'scriptText': r'echo C:\temp\${workspaceFolder}',
            'interpreterPath': r'C:\Windows\system32\cmd.exe',
          },
        ),
        workspaceFolder: '/proj',
        pathStyle: p.Style.posix,
      );

      // Shell text and the executable spec keep their backslashes — only
      // path-shaped fields are re-spelled.
      expect(expanded.extras['scriptText'], r'echo C:\temp\/proj');
      expect(
        expanded.extras['interpreterPath'],
        r'C:\Windows\system32\cmd.exe',
      );
    },
  );

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
      pathStyle: p.Style.posix,
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
