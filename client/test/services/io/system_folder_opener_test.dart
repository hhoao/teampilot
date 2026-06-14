import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/system_folder_opener.dart';

void main() {
  test('invokes the platform runner with the resolved command and path', () async {
    String? seenExe;
    List<String>? seenArgs;
    final opener = SystemFolderOpener(
      isMacOS: false,
      isWindows: true,
      isLinux: false,
      runner: (exe, args) async {
        seenExe = exe;
        seenArgs = args;
      },
    );

    await opener.reveal(r'C:\some\path');

    expect(seenExe, 'explorer');
    expect(seenArgs, [r'C:\some\path']);
  });

  test('uses open on macOS and xdg-open on Linux', () async {
    final calls = <String>[];
    final mac = SystemFolderOpener(
      isMacOS: true, isWindows: false, isLinux: false,
      runner: (exe, _) async => calls.add(exe),
    );
    final linux = SystemFolderOpener(
      isMacOS: false, isWindows: false, isLinux: true,
      runner: (exe, _) async => calls.add(exe),
    );
    await mac.reveal('/p');
    await linux.reveal('/p');
    expect(calls, ['open', 'xdg-open']);
  });

  test('does nothing for empty path', () async {
    var called = false;
    final opener = SystemFolderOpener(
      isMacOS: false, isWindows: false, isLinux: true,
      runner: (_, __) async => called = true,
    );
    await opener.reveal('   ');
    expect(called, isFalse);
  });
}
