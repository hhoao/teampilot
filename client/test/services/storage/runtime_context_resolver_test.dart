import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_resolver.dart';

/// RuntimeContextResolver materializes a RuntimeContext per target kind,
/// reproducing the legacy resolve() platform branches (now the only entry).
void main() {
  test('local target installs native context', () async {
    final tmp = await Directory.systemTemp.createTemp('rcr_local_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final ctx = await resolver.resolve(RuntimeTarget.local());
    expect(ctx.target.kind, RuntimeKind.local);
    expect(ctx.mode, StorageBackendMode.native);
    expect(ctx.appDataRoot, tmp.path);
    expect(ctx.usesPosixPaths, isFalse);
    expect(ctx.cwd, tmp.path);
  });

  test('wsl target forwards distro and is posix', () async {
    final tmp = await Directory.systemTemp.createTemp('rcr_wsl_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    // Off Windows the wsl branch is not taken → native, mirroring legacy
    // resolve(windowsStorageBackend: wsl) off Windows.
    if (Platform.isWindows) return;
    final ctx = await resolver.resolve(RuntimeTarget.wsl('Ubuntu'));
    expect(ctx.target.wslDistro, 'Ubuntu');
    expect(ctx.appDataRoot, tmp.path); // fell back to native off Windows
  });

  test('ssh target with no profile falls back to native off Android', () async {
    if (Platform.isAndroid) return;
    final tmp = await Directory.systemTemp.createTemp('rcr_ssh_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final resolver = RuntimeContextResolver(
      nativeAppDataPath: tmp.path,
      nativeHome: tmp.path,
      nativeCwd: tmp.path,
    );
    final ctx = await resolver.resolve(RuntimeTarget.ssh('p1', label: 'box'));
    expect(ctx.appDataRoot, tmp.path);
    expect(ctx.usesPosixPaths, isFalse);
  });
}
