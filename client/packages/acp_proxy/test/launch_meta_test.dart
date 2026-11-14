import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  final meta = {
    'teampilot': {
      'cli': 'claude',
      'executable': '/usr/local/bin/claude',
      'args': ['--acp'],
      'env': {'HOME': '/home/runner'},
      'permissionPolicy': 'fullAccess',
    },
  };

  test('parses a matching endpoint', () {
    final launch = AcpProxyLaunchMeta.parse(
      endpointCli: 'claude',
      meta: meta,
    );
    expect(launch.executable, '/usr/local/bin/claude');
    expect(launch.args, ['--acp']);
    expect(launch.env['HOME'], '/home/runner');
    expect(launch.permissionPolicy, AcpProxyPermissionPolicy.fullAccess);
  });

  test('rejects a different cli than the port', () {
    expect(
      () => AcpProxyLaunchMeta.parse(endpointCli: 'codex', meta: meta),
      throwsFormatException,
    );
  });

  test('rejects an unknown permission policy', () {
    final bad = {
      'teampilot': {...(meta['teampilot']! as Map), 'permissionPolicy': 'yolo'},
    };
    expect(
      () => AcpProxyLaunchMeta.parse(endpointCli: 'claude', meta: bad),
      throwsFormatException,
    );
  });
}
