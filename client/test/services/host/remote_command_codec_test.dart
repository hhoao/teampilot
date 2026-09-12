import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/flashskyai/remote_flashskyai_command_builder.dart';
import 'package:teampilot/services/host/remote_command_codec.dart';
import 'package:tp_sshd/tp_sshd.dart';

void main() {
  group('RemoteCommandCodec.encodeLegacy', () {
    test('legacy branch is byte-identical to the old builder output', () {
      final legacy = RemoteCommandCodec().encodeLegacy(
        const RemoteCommandSpec(
          argv: ['/usr/local/bin/flashskyai', '--version'],
          cwd: '/home/u/work',
          env: {'FOO': "it's"},
        ),
      );
      final old = RemoteFlashskyaiCommandBuilder().buildCommand(
        remoteExecutablePath: '/usr/local/bin/flashskyai',
        arguments: ['--version'],
        workingDirectory: '/home/u/work',
        environment: {'FOO': "it's"},
      );
      expect(legacy, old); // exact string equality, including the PATH export
    });

    test('login-shell passthrough wraps with the login shell', () {
      final legacy = RemoteCommandCodec().encodeLegacy(
        const RemoteCommandSpec(argv: ['claude', '--resume', 's1']),
        useLoginShell: true,
      );
      final old = RemoteFlashskyaiCommandBuilder().buildCommand(
        remoteExecutablePath: 'claude',
        arguments: ['--resume', 's1'],
        useLoginShell: true,
      );
      expect(legacy, old);
      expect(legacy, startsWith(r'TERM="${TERM:-xterm-256color}" bash -lc '));
    });

    test('null cwd and env keep the builder output unchanged', () {
      final legacy = RemoteCommandCodec().encodeLegacy(
        const RemoteCommandSpec(argv: ['claude']),
      );
      final old = RemoteFlashskyaiCommandBuilder().buildCommand(
        remoteExecutablePath: 'claude',
        arguments: [],
      );
      expect(legacy, old);
      expect(legacy, isNot(contains('cd ')));
    });
  });

  group('RemoteCommandCodec.encodeEmbedded', () {
    test('embedded branch is a tp1: JSON payload', () {
      final payload = RemoteCommandCodec().encodeEmbedded(
        const RemoteCommandSpec(
          argv: ['claude', '--version'],
          cwd: r'C:\work',
          env: {'K': 'V'},
        ),
      );
      expect(
        payload,
        r'tp1:{"argv":["claude","--version"],"cwd":"C:\\work","env":{"K":"V"}}',
      );
      // and the package's decoder accepts it (cross-check):
      expect(TpExecCodec.tryDecode(payload)!.argv, ['claude', '--version']);
    });

    test('omits cwd and env when null or empty', () {
      expect(
        RemoteCommandCodec().encodeEmbedded(
          const RemoteCommandSpec(argv: ['claude']),
        ),
        'tp1:{"argv":["claude"]}',
      );
      expect(
        RemoteCommandCodec().encodeEmbedded(
          const RemoteCommandSpec(argv: ['claude'], cwd: '/w', env: {}),
        ),
        'tp1:{"argv":["claude"],"cwd":"/w"}',
      );
      expect(
        TpExecCodec.tryDecode(
          RemoteCommandCodec().encodeEmbedded(
            const RemoteCommandSpec(argv: ['claude']),
          ),
        )!.cwd,
        isNull,
      );
    });

    test('is byte-identical to TpExecCodec.encode', () {
      const spec = RemoteCommandSpec(
        argv: ['claude', '--version'],
        cwd: '/w',
        env: {'K': 'V'},
      );
      expect(
        RemoteCommandCodec().encodeEmbedded(spec),
        TpExecCodec.encode(
          const SSHExecRequest(
            argv: ['claude', '--version'],
            cwd: '/w',
            env: {'K': 'V'},
          ),
        ),
      );
    });

    test('never adds shell quoting', () {
      final payload = RemoteCommandCodec().encodeEmbedded(
        const RemoteCommandSpec(argv: ['claude', "it's; rm -rf /"]),
      );
      // Structured exec has no shell: the argument stays a raw JSON string.
      expect(payload, 'tp1:{"argv":["claude","it\'s; rm -rf /"]}');
    });
  });
}
