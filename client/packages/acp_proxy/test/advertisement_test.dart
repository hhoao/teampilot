import 'dart:io';

import 'package:acp_proxy/acp_proxy.dart';
import 'package:test/test.dart';

void main() {
  test('parse reads version, pid, and ports', () {
    final ad = AcpProxyAdvertisement.parse('''
{
  "v": 1,
  "version": "0.1.0",
  "bind": "127.0.0.1",
  "pid": 42,
  "clis": { "claude": { "port": 43111 }, "codex": { "port": 43112 } }
}
''');
    expect(ad.version, '0.1.0');
    expect(ad.pid, 42);
    expect(ad.ports, {'claude': 43111, 'codex': 43112});
  });

  test('parse rejects a non-loopback bind', () {
    expect(
      () => AcpProxyAdvertisement.parse(
        '{"v":1,"version":"0.1.0","bind":"0.0.0.0","pid":1,"clis":{}}',
      ),
      throwsFormatException,
    );
  });

  test('write is atomic and round-trips', () async {
    final root = await Directory.systemTemp.createTemp('acp-proxy-ad');
    addTearDown(() => root.delete(recursive: true));
    const ad = AcpProxyAdvertisement(
      version: acpProxyVersion,
      pid: 7,
      ports: {'claude': 43111},
    );
    await writeAcpProxyAdvertisement(root, ad);
    final read = AcpProxyAdvertisement.parse(
      acpProxyAdvertisementFile(root).readAsStringSync(),
    );
    expect(read.version, acpProxyVersion);
    expect(read.pid, 7);
    expect(read.ports['claude'], 43111);
    expect(acpProxyAdvertisementFile(root).path, endsWith('acp-proxy.json'));
  });
}
