import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/io/runtime_folder_opener.dart';
import 'package:teampilot/services/io/system_folder_opener.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';

import '../../support/test_runtime_context.dart';

void main() {
  test('native work context uses the local folder opener', () async {
    String? revealed;
    final opener = RuntimeFolderOpener(
      localOpener: _CapturingLocalOpener((path) => revealed = path),
    );
    final ctx = testRuntimeContext('/home');

    final ok = await opener.reveal(path: '/cfg/claude', workContext: ctx);

    expect(ok, isTrue);
    expect(revealed, '/cfg/claude');
  });

  test('null work context falls back to local opener', () async {
    String? revealed;
    final opener = RuntimeFolderOpener(
      localOpener: _CapturingLocalOpener((path) => revealed = path),
    );

    final ok = await opener.reveal(path: '/local/cfg', workContext: null);

    expect(ok, isTrue);
    expect(revealed, '/local/cfg');
  });

  test('wsl work context runs xdg-open inside wsl.exe', () async {
    final calls = <List<String>>[];
    final opener = RuntimeFolderOpener(
      wslRunner: (exe, args) async {
        calls.add([exe, ...args]);
        return ProcessResult(0, 0, '', '');
      },
    );
    final ctx = RuntimeContext(
      target: RuntimeTarget.wsl('Ubuntu', label: 'WSL'),
      filesystem: WslFilesystem(distro: 'Ubuntu'),
      home: '/home',
      cwd: '/home',
      appDataRoot: '/home/.local/share/com.hhoa.teampilot',
      paths: AppPaths('/home/.local/share/com.hhoa.teampilot'),
    );

    final ok = await opener.reveal(path: '/cfg', workContext: ctx);

    expect(ok, isTrue);
    expect(calls.single, ['wsl.exe', '-d', 'Ubuntu', 'xdg-open', '--', '/cfg']);
  });
}

class _CapturingLocalOpener extends SystemFolderOpener {
  _CapturingLocalOpener(this._onReveal)
      : super(
          isMacOS: true,
          isWindows: false,
          isLinux: false,
          runner: (exe, args) async {},
        );

  final void Function(String path) _onReveal;

  @override
  Future<void> reveal(String path) async => _onReveal(path);
}
