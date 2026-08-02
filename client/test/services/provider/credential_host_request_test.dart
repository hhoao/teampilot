import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/credential_host_request.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

void main() {
  group('CredentialHostRequest', () {
    test('bare path is unchanged', () {
      const preferencePath = '/usr/bin/claude';

      expect(
        CredentialHostRequest.hostExecutable(preferencePath),
        '/usr/bin/claude',
      );
      expect(
        CredentialHostRequest.hostArguments(preferencePath, const ['auth', 'login']),
        ['auth', 'login'],
      );
      expect(CredentialHostRequest.usePosixCliPaths(preferencePath), isFalse);
    });

    test(
      'wsl.exe wrapper on native context keeps wsl.exe',
      () {
        const preferencePath = 'wsl.exe -d Ubuntu /usr/bin/claude';
        const subcommand = ['auth', 'login'];

        expect(
          CredentialHostRequest.hostExecutable(
            preferencePath,
            modeOverride: StorageBackendMode.native,
          ),
          'wsl.exe',
        );
        expect(
          CredentialHostRequest.hostArguments(
            preferencePath,
            subcommand,
            modeOverride: StorageBackendMode.native,
          ),
          ['-d', 'Ubuntu', '/usr/bin/claude', ...subcommand],
        );
        expect(
          CredentialHostRequest.usePosixCliPaths(
            preferencePath,
            modeOverride: StorageBackendMode.native,
          ),
          isTrue,
        );
      },
      skip: Platform.isWindows ? false : 'wsl.exe paths are Windows-only',
    );

    test(
      'wsl.exe wrapper on wsl context unwraps to linux path',
      () {
        const preferencePath = 'wsl.exe -d Ubuntu /usr/bin/claude';
        const subcommand = ['auth', 'login'];

        expect(
          CredentialHostRequest.hostExecutable(
            preferencePath,
            modeOverride: StorageBackendMode.wsl,
          ),
          '/usr/bin/claude',
        );
        expect(
          CredentialHostRequest.hostArguments(
            preferencePath,
            subcommand,
            modeOverride: StorageBackendMode.wsl,
          ),
          subcommand,
        );
        expect(
          CredentialHostRequest.usePosixCliPaths(
            preferencePath,
            modeOverride: StorageBackendMode.wsl,
          ),
          isTrue,
        );
      },
      skip: Platform.isWindows ? false : 'wsl.exe paths are Windows-only',
    );
  });
}
