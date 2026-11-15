import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_proxy_route.dart';

void main() {
  const pinned = '0.1.0';
  const ad = '''
{"v":1,"version":"0.1.0","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}
''';

  test('matching version and a listening pid forwards to that port', () {
    final route = decideAcpProxyRoute(
      advertisementJson: ad,
      pinnedVersion: pinned,
      cliId: 'claude',
      pidListening: true,
    );

    expect(route, isA<AcpProxyForwardRoute>());
    expect((route as AcpProxyForwardRoute).port, 8080);
  });

  test('a missing advertisement keeps SSH exec', () {
    final route = decideAcpProxyRoute(
      advertisementJson: null,
      pinnedVersion: pinned,
      cliId: 'claude',
      pidListening: false,
    );

    expect(route, isA<AcpProxyExecRoute>());
    expect((route as AcpProxyExecRoute).reason, acpProxyRouteMissing);
  });

  test('a version mismatch keeps SSH exec', () {
    final route = decideAcpProxyRoute(
      advertisementJson: ad.replaceAll('0.1.0', '0.0.9'),
      pinnedVersion: pinned,
      cliId: 'claude',
      pidListening: true,
    );

    expect((route as AcpProxyExecRoute).reason, acpProxyRouteVersion);
  });

  test('an unreadable advertisement keeps SSH exec', () {
    final route = decideAcpProxyRoute(
      advertisementJson: '{',
      pinnedVersion: pinned,
      cliId: 'claude',
      pidListening: true,
    );

    expect((route as AcpProxyExecRoute).reason, acpProxyRouteUnreadable);
  });

  test('a cli with no published port keeps SSH exec', () {
    final route = decideAcpProxyRoute(
      advertisementJson: ad,
      pinnedVersion: pinned,
      cliId: 'codex',
      pidListening: true,
    );

    expect((route as AcpProxyExecRoute).reason, acpProxyRouteNoPort);
  });

  test('a pid that is not listening keeps SSH exec', () {
    final route = decideAcpProxyRoute(
      advertisementJson: ad,
      pinnedVersion: pinned,
      cliId: 'claude',
      pidListening: false,
    );

    expect((route as AcpProxyExecRoute).reason, acpProxyRouteNotListening);
  });

  test('proc tcp listen inode is the loopback socket for that port', () {
    const table = '''
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4242 1 0000000000000000 100 0 0 10 0
   1: 0100007F:0050 00000000:0000 01 00000000:00000000 00:00000000 00000000     0        0 99 1 0000000000000000 100 0 0 10 0
''';

    expect(procNetTcpListenInode(table, 8080), 4242);
    expect(procNetTcpListenInode(table, 80), isNull);
  });

  test('fd links prove the pid owns that listen socket', () {
    expect(
      processFdLinksOwnSocket(const ['socket:[4242]', 'pipe:[1]'], 4242),
      isTrue,
    );
    expect(processFdLinksOwnSocket(const ['socket:[7]'], 4242), isFalse);
  });

  test('probe output forwards only when the advertised pid owns the port', () {
    const output = '''
---ACP-PROXY-BINARY---
yes
---ACP-PROXY-PIDFILE---
42
---ACP-PROXY-AD---
{"v":1,"version":"0.1.0","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}
---ACP-PROXY-TCP---
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4242 1 0000000000000000 100 0 0 10 0
---ACP-PROXY-AD-FDS---
socket:[4242]
---ACP-PROXY-PID-FDS---
socket:[4242]
''';

    final route = decideAcpProxyRouteFromProbe(
      output: output,
      pinnedVersion: pinned,
      cliId: 'claude',
    );

    expect((route as AcpProxyForwardRoute).port, 8080);
  });

  test(
    'probe output stays on exec when the socket belongs to someone else',
    () {
      const output = '''
---ACP-PROXY-BINARY---
yes
---ACP-PROXY-PIDFILE---
42
---ACP-PROXY-AD---
{"v":1,"version":"0.1.0","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}
---ACP-PROXY-TCP---
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4242 1 0000000000000000 100 0 0 10 0
---ACP-PROXY-AD-FDS---
pipe:[1]
---ACP-PROXY-PID-FDS---
pipe:[1]
''';

      final route = decideAcpProxyRouteFromProbe(
        output: output,
        pinnedVersion: pinned,
        cliId: 'claude',
      );

      expect((route as AcpProxyExecRoute).reason, acpProxyRouteNotListening);
    },
  );
}
