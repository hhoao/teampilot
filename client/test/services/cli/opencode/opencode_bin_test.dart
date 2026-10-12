import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/cli/opencode/opencode_bin.dart';

void main() {
  test('official v2 bin is ~/.opencode/bin/opencode', () {
    expect(
      opencodeOfficialExecutablePath(
        homeDirectory: '/home/alice',
        isWindows: false,
      ),
      '/home/alice/.opencode/bin/opencode',
    );
    expect(
      opencodeOfficialExecutablePath(
        homeDirectory: r'C:\Users\alice',
        isWindows: true,
      ),
      p.windows.join(r'C:\Users\alice', '.opencode', 'bin', 'opencode.exe'),
    );
  });

  test('npm opencode-ai shims are stale leftover installs', () {
    expect(
      isStaleOpencodeNpmInstall(
        '/home/alice/.local/bin/opencode',
        linkTarget: '../lib/node_modules/opencode-ai/bin/opencode.exe',
      ),
      isTrue,
    );
    expect(isStaleOpencodeNpmInstall('/opt/opencode'), isFalse);
  });

  test('launch prefers official v2 over a saved npm stub', () {
    expect(
      preferOpencodeLaunchExecutable(
        userPath: '/home/alice/.local/bin/opencode',
        discoveredPath: '/home/alice/.local/bin/opencode',
        wellKnownPath: '/home/alice/.opencode/bin/opencode',
        isStaleInstall: (path) =>
            path.contains('.local/bin/opencode') ||
            path.contains('opencode-ai'),
      ),
      '/home/alice/.opencode/bin/opencode',
    );
  });

  test('launch keeps a custom non-stub path when official bin exists', () {
    expect(
      preferOpencodeLaunchExecutable(
        userPath: '/opt/opencode',
        discoveredPath: null,
        wellKnownPath: '/home/alice/.opencode/bin/opencode',
        isStaleInstall: (_) => false,
      ),
      '/opt/opencode',
    );
  });
}
