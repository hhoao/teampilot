import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/remote/remote_os_prober.dart';

void main() {
  group('RemoteOsProber', () {
    const prober = RemoteOsProber();

    test('uname answers → posix (no further probing)', () async {
      final cmds = <String>[];
      final os = await prober.probe((cmd) async {
        cmds.add(cmd);
        return cmd == 'uname -s' ? 'Linux' : '';
      });
      expect(os, RemoteOs.posix);
      expect(cmds, ['uname -s']);
    });

    test('uname empty, %OS% reveals Windows_NT → windows', () async {
      final os = await prober.probe((cmd) async {
        if (cmd == 'echo %OS%') return 'Windows_NT';
        return '';
      });
      expect(os, RemoteOs.windows);
    });

    test('uname empty, ver banner reveals Windows → windows', () async {
      final os = await prober.probe((cmd) async {
        if (cmd == 'ver') return 'Microsoft Windows [Version 10.0.19045.0]';
        return '';
      });
      expect(os, RemoteOs.windows);
    });

    test('all probes silent → posix fallback', () async {
      final os = await prober.probe((_) async => '');
      expect(os, RemoteOs.posix);
    });

    test('macOS uname (Darwin) → posix', () async {
      final os = await prober.probe(
        (cmd) async => cmd == 'uname -s' ? 'Darwin' : '',
      );
      expect(os, RemoteOs.posix);
    });
  });
}
