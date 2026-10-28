# Antigravity CLI (ACP-only) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google Antigravity CLI (`agy`) as a first-class ACP-only TeamPilot CLI with the full non-terminal CLI surface.

**Architecture:** A new `CliTool.antigravity` definition owns one capability per concern. ACP chat uses the official `agy_acp_server` binary; resources are materialized into a per-session fake `HOME` (`<home>/.gemini/config`). Shared infrastructure gains a neutral ACP adapter installer (npm + binary archive), a generic binary installer, and an ACP `usage_update` collector. No PTY path.

**Tech Stack:** Dart 3 / Flutter, `acpd`, `package:archive`, `package:crypto`, `package:http`, `flutter_test`, `dart run tool/run_tests.dart`.

## Global Constraints

- Worktree: `.worktrees/feat-antigravity-acp-cli`, branch `feat/antigravity-acp-cli`.
- Never run bare `flutter test`. Use `cd client && dart run tool/run_tests.dart <path> [--plain-name ...]`.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.
- No `if (cli == CliTool.antigravity)` outside `client/lib/services/cli/antigravity/`; resolve capabilities through `CliToolRegistry`.
- All user-visible strings go through `client/lib/l10n/app_en.arb` and `app_zh.arb`.
- Desktop local Phase 1. SSH/Android ACP and remote install are out of scope.
- Pinned ACP server: **1.4.3**; sha256 values are in Task 4. Never install an unpinned build.
- Fake `HOME` = `<session runtime tool dir>/home`; config root = `<home>/.gemini/config`.
- Commit after every task. Conventional commits (`feat(antigravity): ...`, `feat(acp): ...`).

---

## File Structure

```text
client/lib/services/cli/registry/installer/
  acp_adapter_installer.dart          # neutral interface
  binary_archive_installer.dart       # download/verify/extract helper
  npm_installer_capability.dart       # implements the neutral interface

client/lib/services/cli/antigravity/
  antigravity_tool.dart
  antigravity_bootstrap_entry.dart
  provider_presets.dart
  capabilities/
    acp.dart
    acp_settings.dart
    acp_adapter_installer.dart
    executable.dart
    session.dart
    provider.dart
    mcp.dart
    hook_writer.dart
    plugin.dart
    prompt.dart
    workspace_base_info.dart
    headless.dart
    native_commands.dart
    usage.dart
    defaults.dart
    history/ai_history_capability.dart
    tool_call_resolvers.dart
  provider/
    antigravity_model_catalog.dart
    antigravity_login_dialog.dart

client/lib/services/cli/registry/plugins/
  antigravity_plugin_projector.dart

client/lib/services/acp/
  acp_usage.dart

client/tool/
  antigravity_acp_probe.dart

client/test/services/cli/registry/
  acp_adapter_installer_test.dart
  binary_archive_installer_test.dart
client/test/services/cli/antigravity/
  antigravity_acp_capability_test.dart
  antigravity_registry_test.dart
  antigravity_acp_adapter_test.dart
  antigravity_provider_test.dart
  antigravity_resources_test.dart
  antigravity_hooks_test.dart
  antigravity_plugin_test.dart
  antigravity_prompt_test.dart
  antigravity_headless_test.dart
  antigravity_history_test.dart
  antigravity_usage_test.dart
client/test/services/acp/
  acp_usage_test.dart
client/test/services/install/
  acp_adapter_readiness_test.dart
```

---

### Task 1: Probe the official ACP server

**Files:**
- Create: `client/tool/antigravity_acp_probe.dart`
- Create: `docs/superpowers/notes/2026-10-28-antigravity-acp-probe.md`

**Interfaces:**
- Produces: recorded answers for `HOME` isolation, `--uid`, `initialize` auth,
  `session/new` config, `session/load`, `usage_update`, and `session/cancel`.

- [ ] **Step 1: Write the probe script**

```dart
// client/tool/antigravity_acp_probe.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final adapter = args.isEmpty ? 'agy_acp_server' : args.first;
  final cwd = Directory.current.path;
  final home = Directory.systemTemp.createTempSync('agy-probe-home-').path;
  final process = await Process.start(adapter, const [], environment: {
    ...Platform.environment,
    'HOME': home,
    'USERPROFILE': home,
    'SURFACE': 'teampilot-probe',
  });
  process.stderr.transform(utf8.decoder).listen(stderr.write);
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) => stdout.writeln('<< $line'));

  var id = 0;
  void send(String method, Map<String, Object?> params) {
    final message = jsonEncode({
      'jsonrpc': '2.0',
      'id': ++id,
      'method': method,
      'params': params,
    });
    stdout.writeln('>> $message');
    process.stdin.writeln(message);
  }

  send('initialize', {
    'protocolVersion': 1,
    'clientCapabilities': <String, Object?>{},
  });
  await Future<void>.delayed(const Duration(seconds: 5));
  send('session/new', {'cwd': cwd, 'mcpServers': <Object?>[]});
  await Future<void>.delayed(const Duration(seconds: 40));
  send('session/prompt', {
    'sessionId': 'probe',
    'prompt': [
      {'type': 'text', 'text': 'Reply with exactly: ok'},
    ],
  });
  await Future<void>.delayed(const Duration(seconds: 40));
  process.kill();
  stdout.writeln('HOME=$home');
}
```

- [ ] **Step 2: Download and unpack the adapter manually**

```bash
cd /tmp
curl -fL -o agy-acp.zip \
  https://dl.google.com/agy-extensions/releases/linux/agy-acp-server-1.4.3-linux-x86_64.zip
unzip -o agy-acp.zip -d agy-acp
chmod +x agy-acp/agy_acp_server.par
```

- [ ] **Step 3: Run the probe**

```bash
cd /home/hhoa/git/hhoa/teampilot/client
dart run tool/antigravity_acp_probe.dart /tmp/agy-acp/agy_acp_server.par
```

- [ ] **Step 4: Record the answers**

Create `docs/superpowers/notes/2026-10-28-antigravity-acp-probe.md` with:

```markdown
# Antigravity ACP probe (1.4.3)

- Adapter path:
- HOME isolation: reads/writes under HOME? yes/no
- `--uid`: required? accepted empty? accepted value?
- initialize agentInfo:
- initialize authMethods:
- authenticate required: yes/no
- session/new configOptions:
- session/new model honored: yes/no
- session/new mcpServers honored: yes/no
- session/load: supported / unsupported
- session/list: supported / unsupported
- usage_update payload:
- session/cancel behavior:
- cold start seconds:
- notes:
```

- [ ] **Step 5: Commit**

```bash
git add client/tool/antigravity_acp_probe.dart docs/superpowers/notes/2026-10-28-antigravity-acp-probe.md
git commit -m "chore(antigravity): add ACP probe script and 1.4.3 evidence"
```

---

### Task 2: Neutral ACP adapter installer abstraction

**Files:**
- Create: `client/lib/services/cli/registry/installer/acp_adapter_installer.dart`
- Modify: `client/lib/services/cli/registry/installer/npm_installer_capability.dart`
- Modify: `client/lib/services/cli/registry/capabilities/acp_settings_capability.dart`
- Test: `client/test/services/cli/registry/acp_adapter_installer_test.dart`

**Interfaces:**
- Produces:

```dart
abstract interface class AcpAdapterInstaller {
  /// Stable install-job target id, distinct from any `CliTool.value`.
  /// Claude/Codex keep their existing static `jobTarget` field.
  String get adapterJobTarget;
  String get executableName;
  String get displayName;
  bool get supportsInstaller;
  Future<String?> resolveInstalledPath();
  Future<String?> latestVersion();
  Future<CliInstallResult> install(CliInstallContext context);
}
```

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/acp_adapter_installer_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';

void main() {
  test('npm ACP adapters satisfy the neutral contract', () async {
    const claude = ClaudeAcpAdapterInstaller();
    const codex = CodexAcpAdapterInstaller();
    expect(claude, isA<AcpAdapterInstaller>());
    expect(codex, isA<AcpAdapterInstaller>());
    expect(claude.adapterJobTarget, ClaudeAcpAdapterInstaller.jobTarget);
    expect(codex.adapterJobTarget, CodexAcpAdapterInstaller.jobTarget);
    expect(await claude.resolveInstalledPath(), isNull);
    expect(await claude.latestVersion(), isNull);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/acp_adapter_installer_test.dart`
Expected: FAIL because `acp_adapter_installer.dart` does not exist.

- [ ] **Step 3: Add the interface**

```dart
// client/lib/services/cli/registry/installer/acp_adapter_installer.dart
import '../../installer_types.dart';
import 'installer_context.dart';

abstract interface class AcpAdapterInstaller {
  String get adapterJobTarget;
  String get executableName;
  String get displayName;
  bool get supportsInstaller;
  Future<String?> resolveInstalledPath();
  Future<String?> latestVersion();
  Future<CliInstallResult> install(CliInstallContext context);
}
```

- [ ] **Step 4: Make `NpmInstallerCapability` implement it**

```dart
abstract class NpmInstallerCapability implements AcpAdapterInstaller {
  const NpmInstallerCapability();

  @override
  String get adapterJobTarget => 'adapter:$executableName';

  @override
  Future<String?> resolveInstalledPath() async => null;

  @override
  Future<String?> latestVersion() async => null;

  // existing members stay unchanged
}
```

`ClaudeAcpAdapterInstaller` and `CodexAcpAdapterInstaller` already expose
`static const jobTarget`; their inherited `adapterJobTarget` resolves to the
same string (`adapter:<executableName>`) because their `executableName` values
match the suffix. If a mismatch appears, override `adapterJobTarget` to return
the static value.

- [ ] **Step 5: Change `AcpSettingsCapability.adapterInstaller` type**

```dart
// acp_settings_capability.dart
import '../installer/acp_adapter_installer.dart';

abstract interface class AcpSettingsCapability implements CliCapability {
  bool get usesSeparateAdapter;
  String? get adapterExecutableName;
  AcpAdapterInstaller? get adapterInstaller;
  bool get showsPersonalAcpSwitch;
}
```

Update `DefaultAcpSettingsCapability.adapterInstaller` to the new type.

- [ ] **Step 6: Run test and analyze**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/cli/registry/acp_adapter_installer_test.dart test/services/cli/acp_settings_capability_test.dart
```

- [ ] **Step 7: Commit**

```bash
git add client/lib/services/cli/registry/installer/acp_adapter_installer.dart \
  client/lib/services/cli/registry/installer/npm_installer_capability.dart \
  client/lib/services/cli/registry/capabilities/acp_settings_capability.dart \
  client/test/services/cli/registry/acp_adapter_installer_test.dart
git commit -m "feat(acp): add neutral adapter installer contract"
```

---

### Task 3: Generic binary archive installer

**Files:**
- Create: `client/lib/services/cli/registry/installer/binary_archive_installer.dart`
- Test: `client/test/services/cli/registry/binary_archive_installer_test.dart`

**Interfaces:**
- Produces:

```dart
typedef BinaryArchiveFetcher = Future<File> Function(
  Uri uri, {
  String? expectedSha256,
  void Function(int received, int? total)? onProgress,
  bool Function()? isCancelled,
});

final class BinaryArchiveInstaller {
  const BinaryArchiveInstaller({
    required this.fs,
    required this.fetch,
    this.extract = extractZipArchive,
    this.chmod = chmodExecutable,
  });

  Future<String> install({
    required Uri archiveUri,
    required String sha256,
    required String destDir,
    required String executableName,
    List<String> extraExecutables = const [],
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  });
}
```

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/registry/binary_archive_installer_test.dart
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/installer/binary_archive_installer.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('downloads, verifies, extracts, chmods, and moves atomically', () async {
    final root = Directory.systemTemp.createTempSync('agy-bin-');
    final zipFile = File('${root.path}/adapter.zip');
    final archive = Archive()
      ..addFile(ArchiveFile('agy_acp_server.par', 3, [1, 2, 3]));
    await zipFile.writeAsBytes(ZipEncoder().encode(archive));
    final fs = LocalFilesystem();
    var chmodded = '';

    final installer = BinaryArchiveInstaller(
      fs: fs,
      fetch: (uri, {expectedSha256, onProgress, isCancelled}) async => zipFile,
      chmod: (path) async => chmodded = path,
    );
    final path = await installer.install(
      archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
      sha256: 'ignored-by-fake-fetch',
      destDir: '${root.path}/toolchain/1.4.3',
      executableName: 'agy_acp_server.par',
    );

    expect(path, '${root.path}/toolchain/1.4.3/agy_acp_server.par');
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(chmodded, path);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/binary_archive_installer_test.dart`
Expected: FAIL because the class is missing.

- [ ] **Step 3: Implement the installer**

```dart
// client/lib/services/cli/registry/installer/binary_archive_installer.dart
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';

typedef BinaryArchiveFetcher = Future<File> Function(
  Uri uri, {
  String? expectedSha256,
  void Function(int received, int? total)? onProgress,
  bool Function()? isCancelled,
});
typedef BinaryArchiveExtractor = Future<void> Function({
  required File archive,
  required String destDir,
});
typedef BinaryChmod = Future<void> Function(String path);

Future<void> extractZipArchive({
  required File archive,
  required String destDir,
}) async {
  final bytes = await archive.readAsBytes();
  final decoded = ZipDecoder().decodeBytes(bytes);
  final fs = LocalFilesystem();
  for (final entry in decoded) {
    if (!entry.isFile) continue;
    final out = p.join(destDir, entry.name);
    await fs.ensureDir(p.dirname(out));
    await fs.writeBytes(out, entry.content as List<int>);
  }
}

Future<void> chmodExecutable(String path) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', ['755', path]);
}

final class BinaryArchiveInstaller {
  const BinaryArchiveInstaller({
    required this.fs,
    required this.fetch,
    this.extract = extractZipArchive,
    this.chmod = chmodExecutable,
  });

  final Filesystem fs;
  final BinaryArchiveFetcher fetch;
  final BinaryArchiveExtractor extract;
  final BinaryChmod chmod;

  Future<String> install({
    required Uri archiveUri,
    required String sha256,
    required String destDir,
    required String executableName,
    List<String> extraExecutables = const [],
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final parent = fs.pathContext.dirname(destDir);
    await fs.ensureDir(parent);
    final temp = await fs.createTempDir(prefix: 'agy-acp-', parent: parent);
    final staging = fs.pathContext.join(temp, 'staging');
    await fs.ensureDir(staging);
    try {
      final archive = await fetch(
        archiveUri,
        expectedSha256: sha256,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      await extract(archive: archive, destDir: staging);
      for (final name in [executableName, ...extraExecutables]) {
        final path = fs.pathContext.join(staging, name);
        if (!(await fs.stat(path)).isFile) {
          throw FileSystemException('Archive is missing $name', path);
        }
        await chmod(path);
      }
      if ((await fs.stat(destDir)).exists) {
        await fs.removeRecursive(destDir);
      }
      await fs.rename(staging, destDir);
      return fs.pathContext.join(destDir, executableName);
    } finally {
      if ((await fs.stat(temp)).exists) await fs.removeRecursive(temp);
    }
  }
}
```

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/registry/binary_archive_installer_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/registry/installer/binary_archive_installer.dart \
  client/test/services/cli/registry/binary_archive_installer_test.dart
git commit -m "feat(acp): add binary archive adapter installer"
```

---

### Task 4: Antigravity adapter release catalog + installer

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/acp_adapter_installer.dart`
- Test: `client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart`

**Interfaces:**
- Produces: `AntigravityAcpAdapterInstaller` implementing `AcpAdapterInstaller`,
  pinned version `1.4.3`, platform asset mapping, local install only.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/installer/acp_adapter_installer.dart';

void main() {
  test('maps platform/arch to the pinned ACP asset key', () {
    expect(antigravityAcpAssetKey(os: 'linux', arch: 'x64'), 'linux-x86_64');
    expect(antigravityAcpAssetKey(os: 'linux', arch: 'arm64'), 'linux-aarch64');
    expect(antigravityAcpAssetKey(os: 'darwin', arch: 'x64'), 'darwin-x86_64');
    expect(antigravityAcpAssetKey(os: 'darwin', arch: 'arm64'), 'darwin-aarch64');
    expect(antigravityAcpAssetKey(os: 'windows', arch: 'x64'), 'windows-x86_64');
    expect(antigravityAcpAssetKey(os: 'windows', arch: 'arm64'), 'windows-aarch64');
  });

  test('exposes the neutral contract and pins the version', () {
    const installer = AntigravityAcpAdapterInstaller();
    expect(installer, isA<AcpAdapterInstaller>());
    expect(installer.adapterJobTarget, AntigravityAcpAdapterInstaller.jobTarget);
    expect(
      installer.executableName,
      anyOf('agy_acp_server.par', 'agy_acp_server.exe'),
    );
    expect(installer.supportsInstaller, isTrue);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_adapter_test.dart`
Expected: FAIL because the class is missing.

- [ ] **Step 3: Implement the catalog + installer**

```dart
// client/lib/services/cli/antigravity/capabilities/acp_adapter_installer.dart
import 'dart:io';

import '../../../../services/storage/home_storage.dart';
import '../../installer_types.dart';
import '../../registry/installer/acp_adapter_installer.dart';
import '../../registry/installer/binary_archive_installer.dart';

const antigravityAcpVersion = '1.4.3';

String antigravityAcpAssetKey({required String os, required String arch}) {
  final a = arch == 'arm64' ? 'aarch64' : 'x86_64';
  return '$os-$a';
}

const antigravityAcpSha256 = <String, String>{
  'darwin-aarch64': 'c57db0a9b8b712daa9c3c17cdb990a61842ea569f279e8bd79d7aa85a303b20b',
  'darwin-x86_64': '9392dbbdad7f0663dbfb5a0bf641297b0cf80d2ee9cd2d49a616bbbc7378731d',
  'linux-x86_64': '0634ce5306ba92c932945455e7a83fda78e2d99c33fa8aa6ee0566206a382714',
  'linux-aarch64': '05c153443b0b1175151c760eeddea538950bc9843e317d54786a1f03670182bc',
  'windows-x86_64': '54c2e16378d9a4952e1da70e355f3c33c4f284308d6de48ab3e6e34a127bd325',
  'windows-aarch64': 'fcd46431ad33d3b510ce0b98fe7b43d095bd8b3f1c363ee2d57faa7ee981c7bb',
};

String antigravityAcpArchiveUrl(String assetKey) {
  final folder = assetKey.startsWith('darwin') ? 'macos' : assetKey.split('-').first;
  return 'https://dl.google.com/agy-extensions/releases/$folder/'
      'agy-acp-server-$antigravityAcpVersion-$assetKey.zip';
}

final class AntigravityAcpAdapterInstaller implements AcpAdapterInstaller {
  const AntigravityAcpAdapterInstaller({this.storage, this.binary});

  static const jobTarget = 'adapter:antigravity-acp';

  final HomeStorage? storage;
  final BinaryArchiveInstaller? binary;

  @override
  String get adapterJobTarget => jobTarget;

  @override
  String get executableName =>
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par';

  @override
  String get displayName => 'Antigravity ACP adapter';

  @override
  bool get supportsInstaller => true;

  String _installDir(HomeStorage s) => s.fs.pathContext.join(
    s.appDataRoot,
    'toolchain',
    'antigravity-acp',
    antigravityAcpVersion,
  );

  String _exeName() =>
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par';

  @override
  Future<String?> resolveInstalledPath() async {
    final s = storage;
    if (s == null) return null;
    final path = s.fs.pathContext.join(_installDir(s), _exeName());
    return (await s.fs.stat(path)).isFile ? path : null;
  }

  @override
  Future<String?> latestVersion() async => antigravityAcpVersion;

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    final s = storage;
    final installer = binary;
    if (s == null || installer == null) {
      return const CliInstallResult(
        success: false,
        message: 'Antigravity adapter installer is not configured.',
      );
    }
    if (context.mode == CliInstallMode.ssh) {
      return const CliInstallResult(
        success: false,
        message: 'Remote Antigravity adapter install is not available yet.',
      );
    }
    final asset = antigravityAcpAssetKey(
      os: context.host.isWindows ? 'windows' : (Platform.isMacOS ? 'darwin' : 'linux'),
      arch: Platform.version.contains('arm64') ? 'arm64' : 'x64',
    );
    context.host.report(CliInstallPhase.installingCli);
    final path = await installer.install(
      archiveUri: Uri.parse(antigravityAcpArchiveUrl(asset)),
      sha256: antigravityAcpSha256[asset]!,
      destDir: _installDir(s),
      executableName: _exeName(),
      // Probe 1.4.3: every platform needs the sidecar next to the .par.
      extraExecutables: [
        Platform.isWindows
            ? 'localharness_external.exe'
            : 'localharness_external',
      ],
      onProgress: (received, total) => context.host.report(
        CliInstallPhase.installingCli,
        detail: total == null ? '$received bytes' : '$received/$total',
      ),
      isCancelled: () => context.host.isCancelled,
    );
    return CliInstallResult(
      success: true,
      message: 'Antigravity ACP adapter installed.',
      executablePath: path,
    );
  }
}
```

In production, `binary` is constructed in `app_shell.dart` from
`RemoteDownloader` in Task 7 so the installer actually downloads. The unit test
injects a fake `BinaryArchiveInstaller` or only checks mapping/contract.

- [ ] **Step 4: Run the test**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_adapter_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/cli/antigravity/capabilities/acp_adapter_installer.dart \
  client/test/services/cli/antigravity/antigravity_acp_adapter_test.dart
git commit -m "feat(antigravity): add pinned ACP adapter installer"
```

---

### Task 5: Generalize readiness + install jobs for non-npm adapters

**Files:**
- Modify: `client/lib/services/install/install_job_keys.dart`
- Modify: `client/lib/services/install/install_job_enqueue.dart`
- Modify: `client/lib/services/install/runners/cli_install_job_runner.dart`
- Modify: `client/lib/services/cli/cli_installer_service.dart`
- Modify: `client/lib/services/remote/remote_preflight_cli_install.dart`
- Modify: `client/lib/services/remote/remote_cli_readiness.dart`
- Modify: `client/lib/pages/config/cli_readiness_card.dart`
- Modify: `client/lib/pages/home_workspace/workspace/local_cli_readiness_banner.dart`
- Modify: `client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/services/cli/installer_types.dart`
- Test: `client/test/services/install/acp_adapter_readiness_test.dart`

**Interfaces:**
- Consumes: `AcpAdapterInstaller` from Task 2.
- Produces: `InstallJobKeys.acpAdapter(installer.adapterJobTarget, scope:)`,
  generic `InstallJobRegistry.installAcpAdapter`, and `downloading`/`extracting`
  install phases.

- [ ] **Step 1: Write the failing test**

```dart
// client/test/services/install/acp_adapter_readiness_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/services/install/install_job_keys.dart';

void main() {
  test('adapter install keys are target-scoped, not Claude/Codex-only', () {
    const scope = InstallJobScopeLocal();
    final key = InstallJobKeys.acpAdapter('adapter:antigravity-acp', scope: scope);
    expect(key.target, 'adapter:antigravity-acp');
    expect(key, isNot(InstallJobKeys.claudeAcpAdapter(scope: scope)));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/install/acp_adapter_readiness_test.dart`
Expected: FAIL because `acpAdapter` is missing.

- [ ] **Step 3: Add the generic key + enqueue path**

```dart
// install_job_keys.dart
static InstallJobKey acpAdapter(
  String target, {
  InstallJobScope scope = const InstallJobScopeLocal(),
}) => InstallJobKey(
  kind: InstallJobKind.cliExecutable,
  target: target,
  scope: scope,
);
```

```dart
// install_job_enqueue.dart — add next to installClaudeAcpAdapter
Future<CliInstallResult> installAcpAdapter({
  required AcpAdapterInstaller installer,
  required String title,
  String? subtitle,
  InstallJobScope scope = const InstallJobScopeLocal(),
  FutureOr<void> Function(CliInstallResult result)? onSucceeded,
  FutureOr<void> Function(Object error)? onFailed,
}) {
  final runnerRegistry = this.runnerRegistry;
  if (runnerRegistry == null) {
    throw StateError('InstallJobRegistry has no runner registry');
  }
  final key = InstallJobKeys.acpAdapter(installer.adapterJobTarget, scope: scope);
  final runner = runnerRegistry.resolve(key);
  if (runner == null) {
    throw StateError('No InstallJobRunner for ${key.kind}');
  }
  late final InstallJobSpec<CliInstallResult> spec;
  spec = InstallJobSpec(
    key: key,
    title: title,
    subtitle: subtitle,
    cancelPolicy: InstallCancelPolicy.cooperative,
    onSucceeded: onSucceeded,
    onFailed: onFailed,
    run: (ctx) => runner.run(spec, ctx),
  );
  return enqueue(spec);
}
```

- [ ] **Step 4: Replace hardcoded adapter branches**

`cli_install_job_runner.dart`:

```dart
CliInstallJobRunner({
  required CliInstallerService Function() installerFactory,
  SshProfileById? sshProfileById,
  AcpAdapterInstaller? Function(String target)? adapterResolver,
}) : _installerFactory = installerFactory,
     _sshProfileById = sshProfileById,
     _adapterResolver = adapterResolver;

AcpAdapterInstaller? _adapterFor(String target) =>
    _adapterResolver?.call(target) ??
    (target == ClaudeAcpAdapterInstaller.jobTarget
        ? const ClaudeAcpAdapterInstaller()
        : target == CodexAcpAdapterInstaller.jobTarget
            ? const CodexAcpAdapterInstaller()
            : null);
```

`app_shell.dart` supplies a resolver built from the registry:

```dart
adapterResolver: (target) {
  final registry = CliToolRegistry.builtIn();
  for (final def in registry.launchable) {
    final installer = registry
        .capability<AcpSettingsCapability>(def.id)
        ?.adapterInstaller;
    if (installer != null && installer.adapterJobTarget == target) {
      return installer;
    }
  }
  return null;
},
```

`cli_readiness_card.dart`:

```dart
InstallJobKey _adapterJobKey(BuildContext context) {
  final installer = _settings?.adapterInstaller;
  return InstallJobKeys.acpAdapter(
    installer?.adapterJobTarget ?? 'adapter:unknown',
    scope: installJobScopeForContext(context),
  );
}

final result = installer == null
    ? const CliInstallResult(success: false, message: 'No adapter installer')
    : await jobs.installAcpAdapter(
        installer: installer,
        title: title,
        onSucceeded: onSucceeded,
      );
```

`local_cli_readiness_banner.dart` and
`remote_cli_machine_readiness_panel.dart`: replace the
`is CodexAcpAdapterInstaller` ternaries with
`InstallJobKeys.acpAdapter(installer.adapterJobTarget, scope: scope)`.

Version probing must preserve npm adapters:

```dart
Future<String?> _adapterLatest(AcpAdapterInstaller adapter) async {
  if (adapter is NpmInstallerCapability) {
    return _probe.latestNpm(adapter.npmPackage);
  }
  return adapter.latestVersion();
}
```

Use `_adapterLatest` instead of `adapter.latestVersion()` directly. Task 2's
`NpmInstallerCapability.latestVersion()` returns `null`, so a blind switch
would silently remove Claude/Codex adapter update badges. Also remove the
temporary `as NpmInstallerCapability` casts Task 2 added in
`client/test/pages/config/cli_config_section_test.dart` and
`client/test/services/install/runners/cli_install_job_runner_test.dart`.

- [ ] **Step 5: Neutralize service parameter types**

`CliInstallerService.installAdapter` and
`remote_preflight_cli_install.buildRemotePreflightAdapterInstall` take
`AcpAdapterInstaller` instead of `NpmInstallerCapability`.
`remote_cli_readiness.dart`'s `AdapterInstallActionBuilder` uses
`AcpAdapterInstaller`.

- [ ] **Step 6: Add install phases**

Add `downloading` and `extracting` to `CliInstallPhase` and handle them in
`_cliInstallPhaseLabel` and `remoteCliInstallProgressLabel`:

```dart
CliInstallPhase.downloading => 'Downloading adapter',
CliInstallPhase.extracting => 'Extracting adapter',
```

- [ ] **Step 7: Run tests**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/install/acp_adapter_readiness_test.dart test/services/remote/remote_cli_readiness_adapter_test.dart test/services/cli/acp_settings_capability_test.dart
```

- [ ] **Step 8: Commit**

```bash
git add client/lib/services/install client/lib/services/remote client/lib/services/cli/cli_installer_service.dart \
  client/lib/services/cli/installer_types.dart client/lib/pages/config/cli_readiness_card.dart \
  client/lib/pages/home_workspace/workspace/local_cli_readiness_banner.dart \
  client/lib/pages/home_workspace/workspace/remote_cli_machine_readiness_panel.dart \
  client/lib/app/app_shell.dart client/test/services/install/acp_adapter_readiness_test.dart
git commit -m "feat(acp): generalize adapter readiness and install jobs"
```

---

### Task 6: Vertical slice — enum, tool, ACP, session, executable, registry

**Files:**
- Modify: `client/lib/models/team_config.dart`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Create: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/acp.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/acp_settings.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/session.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/executable.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/defaults.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/provider.dart`
- Modify: `client/lib/services/cli/registry/capabilities/acp_capability.dart`
- Modify: `client/lib/services/cli/registry/built_in_cli_tools.dart`
- Test: `client/test/services/cli/antigravity/antigravity_acp_capability_test.dart`
- Test: `client/test/services/cli/antigravity/antigravity_registry_test.dart`

**Interfaces:**
- Produces: `AntigravityCliTool`, `AntigravityAcpCapability`,
  `AntigravityAcpSettings`, `AntigravityCliSessionCapability`,
  `AntigravityExecutableCapability`, a working official-only provider.
- Adds `Duration get startupTimeout` to `AcpCapability` (default 30 s).

- [ ] **Step 1: Write the failing ACP test**

```dart
// client/test/services/cli/antigravity/antigravity_acp_capability_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/acp.dart';

void main() {
  test('uses the separate ACP server with no CLI flags', () {
    const cap = AntigravityAcpCapability(linuxUid: false);
    expect(cap.agentExecutable('/usr/bin/agy'), 'agy_acp_server.par');
    expect(cap.launchArgCandidates('agy_acp_server.par'), [
      ['agy_acp_server.par'],
    ]);
    expect(cap.acpOnly, isTrue);
    expect(cap.forwardSessionNewMcpServers, isFalse);
    expect(cap.authenticateMethodId, isNull);
  });

  test('isolates HOME and passes the model env', () {
    const cap = AntigravityAcpCapability(
      linuxUid: false,
      model: 'gemini-3.8-flash-medium',
    );
    final env = cap.buildEnvironment(
      sessionToolDir: '/runtime/sessions/s1/antigravity',
      workingDirectory: '/work',
      baseEnv: const {'PATH': '/bin'},
    );
    expect(env['HOME'], '/runtime/sessions/s1/antigravity/home');
    expect(env['USERPROFILE'], '/runtime/sessions/s1/antigravity/home');
    expect(env['GEMINI_HOME'], '/runtime/sessions/s1/antigravity/home/.gemini');
    expect(env['AGY_ACP_DEFAULT_MODEL'], 'gemini-3.8-flash-medium');
    expect(env['PATH'], '/bin');
  });

  test('Linux adapter candidates include the empty uid form first', () {
    const cap = AntigravityAcpCapability(linuxUid: true);
    expect(cap.launchArgCandidates('server'), [
      ['server', '--uid='],
      ['server'],
    ]);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_acp_capability_test.dart`
Expected: FAIL because the files are missing.

- [ ] **Step 3: Add `startupTimeout` to the ACP interface**

```dart
// acp_capability.dart
Duration get startupTimeout => const Duration(seconds: 30);
```

`AcpConnection.initialize` currently has a 15 s `timeout` parameter
(`acp_connection.dart:257`) and `newSession` has 30 s parameters
(`acp_connection.dart:400,435`). Pass `cap.startupTimeout` from
`AcpSessionRuntime.start` to both calls. Do not change the prompt or
permission timeouts.

- [ ] **Step 4: Implement the ACP capability**

```dart
// client/lib/services/cli/antigravity/capabilities/acp.dart
import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class AntigravityAcpTranslator extends AcpAgentTranslator {
  const AntigravityAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      if (suppressAbort && error.message.contains('aborted')) {
        return acpStopCancelled;
      }
      if (error.code == ErrorCode.authRequired.code ||
          (error.code == -32000 &&
              error.message.contains('Authentication required'))) {
        return acpStopAuthRequired;
      }
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class AntigravityAcpCapability
    implements AcpCapability, AcpOnlyCapability {
  const AntigravityAcpCapability({
    this.model,
    this.adapterPath,
    this.linuxUid,
  });

  final String? model;
  final String? adapterPath;
  final bool? linuxUid;

  bool get _usesUid => linuxUid ?? false;

  @override
  bool get acpOnly => true;

  @override
  String agentExecutable(String cliExecutable) =>
      adapterPath ??
      (Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par');

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    // Probe 1.4.3: --uid is a privilege-drop flag, not an account id.
    // Empty disables the switch; a non-empty value must be an existing group.
    if (_usesUid) [executable, '--uid='],
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const AntigravityAcpTranslator();

  @override
  String? get authenticateMethodId => null;

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

  @override
  Duration get startupTimeout => const Duration(seconds: 120);

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final home = '$sessionToolDir/home';
    final env = Map<String, String>.of(baseEnv)
      ..['HOME'] = home
      ..['USERPROFILE'] = home
      ..['GEMINI_HOME'] = '$home/.gemini';
    final m = model?.trim() ?? '';
    if (m.isNotEmpty) env['AGY_ACP_DEFAULT_MODEL'] = m;
    return env;
  }
}
```

In production the ACP capability is constructed with `linuxUid:
Platform.isLinux` (Task 15). No persisted uid exists.

- [ ] **Step 5: Implement session + settings + executable**

`session.dart`:

```dart
final class AntigravityCliSessionCapability extends NoopCliSessionCapability {
  const AntigravityCliSessionCapability();

  String _home(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
  }) => p.join(
    layout.sessionRuntimeToolDir(
      workspaceId,
      sessionId,
      tool.value,
      memberId: memberId,
    ),
    'home',
  );

  @override
  String? sessionIsolatedHomeRoot(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => _home(layout, tool,
      workspaceId: workspaceId, sessionId: sessionId, memberId: memberId);

  @override
  String sessionConfigDir(
    RuntimeLayout layout,
    CliTool tool, {
    required String workspaceId,
    required String sessionId,
    String? memberId,
    String? teamId,
  }) => p.join(
    _home(layout, tool,
        workspaceId: workspaceId, sessionId: sessionId, memberId: memberId),
    '.gemini',
    'config',
  );

  @override
  Future<String> prepareSessionIsolatedHome({
    required Filesystem fs,
    required String canonicalHome,
  }) async {
    await fs.ensureDir(canonicalHome);
    return canonicalHome;
  }
}
```

`acp_settings.dart`:

```dart
final class AntigravityAcpSettings implements AcpSettingsCapability {
  const AntigravityAcpSettings({this.installer});

  final AcpAdapterInstaller? installer;

  @override
  bool get usesSeparateAdapter => true;
  @override
  String? get adapterExecutableName =>
      Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par';
  @override
  AcpAdapterInstaller? get adapterInstaller => installer;
  @override
  bool get showsPersonalAcpSwitch => false;
}
```

`executable.dart`:

```dart
final class AntigravityExecutableCapability implements CliExecutableCapability {
  const AntigravityExecutableCapability();

  @override
  String get defaultExecutableName => 'agy';

  @override
  String get preferencesPathKey => 'cli.antigravity.path';

  @override
  String label(AppLocalizations l10n) => l10n.appProviderToolAntigravity;

  @override
  bool get supportsInstaller => true;

  @override
  Future<String?> locateRemote(SshCommandRunner run) =>
      const DefaultRemoteCliLocator('agy').locate(run);

  @override
  Future<CliInstallResult> install(CliInstallContext context) async {
    if (context.mode == CliInstallMode.ssh) {
      return const CliInstallResult(
        success: false,
        message: 'Remote Antigravity CLI install is not available yet.',
      );
    }
    context.host.report(CliInstallPhase.installingCli);
    final script = context.host.isWindows
        ? 'irm https://antigravity.google/cli/install.ps1 | iex'
        : 'curl -fsSL https://antigravity.google/cli/install.sh | bash';
    final result = await context.host.runLocal(
      context.host.isWindows
          ? CliInstallerCommand('powershell', ['-NoProfile', '-Command', script])
          : CliInstallerCommand.unixShellScript(script),
      phase: CliInstallPhase.installingCli,
      streamOutput: true,
    );
    if (result.exitCode != 0) {
      return CliInstallResult(
        success: false,
        message: installerFailureMessage('Antigravity CLI install failed', result),
      );
    }
    final path = await context.host.locateExecutable('agy');
    return CliInstallResult(
      success: path != null,
      message: path == null
          ? 'agy installed but was not found on PATH.'
          : 'Antigravity CLI installed.',
      executablePath: path,
    );
  }

  @override
  CliExecutablePathRowSpec get executablePathRowSpec =>
      const CliExecutablePathRowSpec(
        titleKey: null,
        subtitleKey: null,
        fieldKey: 'antigravity-cli-executable-path-field',
        browseKey: 'antigravity-cli-executable-path-browse-button',
        resetKey: 'antigravity-cli-executable-path-reset-button',
        debouncerTag: 'antigravity_cli_executable_path',
        installKey: 'antigravity-cli-install-button',
      );
}
```

Add `appProviderToolAntigravity` to both ARB files now so `label` compiles.

- [ ] **Step 6: Create the tool from the CodeBuddy template**

Copy `client/lib/services/cli/codebuddy/codebuddy_tool.dart` to
`client/lib/services/cli/antigravity/antigravity_tool.dart`, then:

- Rename `CodebuddyCliTool` → `AntigravityCliTool`, `id` → `CliTool.antigravity`.
- Replace provider/session/executable/ACP classes with the Antigravity ones.
- Use `DefaultSkillCapability`, `DefaultMemberConfigInspection`,
  `AcpAskFullAccessCliLaunchSecurityCapability`, `UserExtraArgsProvider`.
- Copy `codebuddy/capabilities/defaults.dart` to
  `antigravity/capabilities/defaults.dart`, rename classes to `Antigravity*`,
  set `doneEventNames = const {'Stop'}`, and make `AntigravityNativeCommands`
  return `const []`.
- Delete the copied headless, history, usage, MCP, hooks, prompt, and native
  command fields/imports/capabilities from the tool for this task; Tasks 8–14
  add them back. Keep executable, session, provider, team behavior, terminal
  behavior, member inspection, plugin (copy Gemini's no-op
  `GeminiPluginCapability` into `antigravity/capabilities/plugin.dart` and
  rename it), chat interaction, runtime events, skill, workspace info, launch
  security, user args, ACP, and ACP settings — the registry's
  required-capability asserts cover exactly that set.

- [ ] **Step 7: Create a working official-only provider**

Copy `client/lib/services/cli/gemini/capabilities/provider.dart` to
`antigravity/capabilities/provider.dart`, then:

- Rename `GeminiProviderCapability` → `AntigravityProviderCapability`.
- `catalogCli` → `CliTool.antigravity`; `defaultOfficialProviderId` →
  `'antigravity'`; presets → `AntigravityProviderPresets`.
- Model catalog → the static fallback from Task 7.
- `materializeSessionHome` writes nothing yet (returns
  `const SessionHomeContribution()`); Task 7 adds settings/auth.

- [ ] **Step 8: Register and test**

Add `antigravity` to `CliTool` and import/register the tool in
`built_in_cli_tools.dart`. Adding the enum value breaks every exhaustive
`switch`; do a compile-fix pass now with minimal real entries (Task 15 only
polishes the copy/assets):

- `l10n_extensions.dart`: `CliTool.antigravity => l10n.appProviderToolAntigravity`.
- `widgets/cli/cli_brand_icon.dart`: `'antigravity'` → an existing icon key.
- `pages/usage/usage_format.dart`: label `'Antigravity'`, any brand color.
- `widgets/app_provider/provider_credential_messages.dart` and
  `provider_credential_action_bar.dart`: generic sign-in/success/failure copy.
- `services/storage/workspace_cli_cache.dart`: the ACP-only `const []` arm.

Add a minimal executable test:

```dart
// client/test/services/cli/antigravity/antigravity_executable_test.dart
test('executable defaults to agy and supports local install', () {
  const cap = AntigravityExecutableCapability();
  expect(cap.defaultExecutableName, 'agy');
  expect(cap.preferencesPathKey, 'cli.antigravity.path');
  expect(cap.supportsInstaller, isTrue);
});
```

Then regenerate l10n and run:

```bash
cd client
flutter gen-l10n
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/cli/antigravity
```

The registry test must pass before continuing.

- [ ] **Step 9: Commit**

```bash
git add client/lib/models/team_config.dart client/lib/services/cli/antigravity \
  client/lib/services/cli/registry/capabilities/acp_capability.dart \
  client/lib/services/cli/registry/built_in_cli_tools.dart client/lib/l10n \
  client/test/services/cli/antigravity
git commit -m "feat(antigravity): register ACP-only CLI vertical slice"
```

---

### Task 7: Provider, models, auth, and login

**Files:**
- Create: `client/lib/services/cli/antigravity/provider/antigravity_model_catalog.dart`
- Create: `client/lib/services/cli/antigravity/provider/antigravity_login_dialog.dart`
- Create: `client/lib/services/cli/antigravity/provider_presets.dart`
- Create: `client/lib/services/cli/antigravity/antigravity_bootstrap_entry.dart`
- Modify: `client/lib/services/cli/antigravity/capabilities/provider.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/cli/antigravity/antigravity_provider_test.dart`

**Interfaces:**
- Produces: `AntigravityModelCatalog.parseModels`, static fallback,
  `AntigravityProviderCapability` with `InteractiveCliLoginCapability`,
  `AntigravityBootstrapEntry`.

- [ ] **Step 1: Write the failing model parser test**

```dart
test('parses agy models output', () {
  const output = '''
gemini-4-argon-high       Gemini 4 Argon (High)
gemini-3.8-flash-medium  Gemini 3.8 Flash (Medium)
''';
  expect(AntigravityModelCatalog.parseModels(output), [
    'gemini-4-argon-high',
    'gemini-3.8-flash-medium',
  ]);
});

test('falls back to the documented catalog', () {
  expect(AntigravityModelCatalog.fallback, contains('gemini-4-argon-high'));
});
```

- [ ] **Step 2: Implement the catalog**

```dart
abstract final class AntigravityModelCatalog {
  static const fallback = <String>[
    'gemini-4-argon-high',
    'gemini-4-argon-medium',
    'gemini-3.8-flash-high',
    'gemini-3.8-flash-medium',
    'gemini-3.7-flash-high',
    'gemini-3.7-flash-medium',
    'gemini-3.6-flash-high',
    'gemini-3.6-flash-medium',
    'gemini-3.1-pro-high',
  ];

  static List<String> parseModels(String stdout) => [
    for (final line in stdout.split('\n'))
      if (line.trim().isNotEmpty) line.trim().split(RegExp(r'\s+')).first,
  ];
}
```

- [ ] **Step 3: Extend the provider**

In `AntigravityProviderCapability`:

```dart
@override
List<ModelCatalogSource> get catalogSources => const [
  _AntigravityCatalogSource(),
];

@override
Future<ProviderCatalogSnapshot> loadFromLiveSources(
  ProviderCatalogLoadContext context,
) async => const ProviderCatalogSnapshot();

@override
Future<SessionHomeContribution> materializeSessionHome(
  SessionHomeContext ctx,
) async {
  final toolDir = ctx.paths.sessionToolDir(
    ctx.workspaceId,
    ctx.sessionId,
    'antigravity',
    memberId: ctx.memberId,
  );
  final home = ctx.paths.pathContext.join(toolDir, 'home');
  final cliDir = ctx.paths.pathContext.join(home, '.gemini', 'antigravity-cli');
  final acpDir = ctx.paths.pathContext.join(home, '.gemini', 'antigravity-acp');
  await ctx.paths.fs.ensureDir(cliDir);
  await ctx.paths.fs.ensureDir(acpDir);
  final model = ctx.member?.model ?? ctx.preset?.model ?? '';
  await _mergeJson(
    ctx.paths.fs,
    ctx.paths.pathContext.join(cliDir, 'settings.json'),
    {'model': model},
  );
  await _mergeJson(
    ctx.paths.fs,
    ctx.paths.pathContext.join(acpDir, 'settings.json'),
    {'auth': {'type': _authType(ctx)}},
  );
  return SessionHomeContribution(environment: _authEnv(ctx));
}
```

Keep the helper bodies small and real:

```dart
String _authType(SessionHomeContext ctx) {
  final id = ctx.resolvedProviderId ?? '';
  return id.contains('gemini') ? 'gemini-api-key' : 'oauth-personal';
}

Map<String, String> _authEnv(SessionHomeContext ctx) {
  // Implemented in the next step from the resolved AppProviderConfig.
  return const {};
}

Future<void> _mergeJson(
  Filesystem fs,
  String path,
  Map<String, Object?> patch,
) async {
  final existingText = await fs.readString(path);
  final existing = existingText == null || existingText.trim().isEmpty
      ? <String, Object?>{}
      : (jsonDecode(existingText) as Map).cast<String, Object?>();
  final merged = <String, Object?>{...existing, ...patch};
  await fs.ensureDir(fs.pathContext.dirname(path));
  await fs.atomicWrite(
    path,
    const JsonEncoder.withIndent('  ').convert(merged),
  );
}
```

**Provider resolution:** copy
`CodebuddyProviderCapability._resolveLaunchProvider`,
`_resolveModel`, and `_resolveEffort` into
`AntigravityProviderCapability`, changing only the env/config mapping:

| TeamPilot provider | Antigravity CLI setting / env |
|---|---|
| official Google account | `auth.type: oauth-personal` |
| Gemini API key | `modelProvider: gemini`; `GEMINI_API_KEY`; optional `GOOGLE_GEMINI_BASE_URL` |
| ADC | `AGY_ADC_AUTH=true`; `GOOGLE_CLOUD_PROJECT`; `GOOGLE_CLOUD_LOCATION` |

`_authEnv` returns those env entries; API keys are never written to
`settings.json`. `_resolveModel` uses `provider.defaultModel` or the member
model; `_resolveEffort` maps `low|medium|high`.

`InteractiveCliLoginCapability`:

```dart
@override
String get loginExecutableName => 'agy';

@override
List<String> get loginArguments => const [];

@override
Widget buildLoginDialog(
  BuildContext context, {
  required AppProviderConfig provider,
  required String executable,
}) => AntigravityLoginDialog(
  provider: provider,
  executable: executable,
  storage: storage,
);
```

The dialog is an embedded terminal (copy
`codebuddy/provider/codebuddy_login_dialog.dart`) running `agy` with an
isolated `HOME`; on Done it runs `agy models` to verify.

- [ ] **Step 4: Add the bootstrap entry**

```dart
final class AntigravityBootstrapEntry implements CliBootstrapEntry {
  const AntigravityBootstrapEntry({
    required this.storage,
    required this.acpInstaller,
  });

  final HomeStorage storage;
  final AntigravityAcpAdapterInstaller acpInstaller;
}
```

Wire it in `app_shell.dart`:

```dart
CliTool.antigravity: AntigravityBootstrapEntry(
  storage: homeStorage,
  acpInstaller: AntigravityAcpAdapterInstaller(
    storage: homeStorage,
    binary: BinaryArchiveInstaller(
      fs: homeStorage.fs,
      fetch: (uri, {expectedSha256, onProgress, isCancelled}) =>
          remoteDownloader.fetch(
            uri,
            destFileName: 'antigravity-acp.zip',
            expectedSha256: expectedSha256,
            onProgress: onProgress,
            isCancelled: isCancelled,
          ),
    ),
  ),
),
```

Use the existing `remoteDownloader`/`http.Client` instance in `app_shell.dart`;
do not create a new client per launch.

- [ ] **Step 5: Run tests and commit**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_provider_test.dart
git add client/lib/services/cli/antigravity client/lib/app/app_shell.dart \
  client/test/services/cli/antigravity/antigravity_provider_test.dart
git commit -m "feat(antigravity): add models, provider settings, and login"
```

---

### Task 8: Skills and MCP

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/mcp.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_resources_test.dart`

**Interfaces:**
- Produces: `AntigravityMcpCapability.write` → `<configDir>/mcp_config.json`.
- Skills remain `DefaultSkillCapability` (`<configDir>/skills`).

- [ ] **Step 1: Write the failing test**

```dart
test('writes mcp_config.json with mcpServers', () async {
  final fs = InMemoryFilesystem();
  const cap = AntigravityMcpCapability();
  await cap.write(
    fs: fs,
    configDir: '/cfg',
    servers: const [
      StdioMcpServer(name: 'bus', command: 'node', args: ['bus.js']),
      RemoteMcpServer(name: 'remote', url: 'https://example.test/mcp'),
    ],
  );
  final text = await fs.readString('/cfg/mcp_config.json');
  expect(text, contains('"mcpServers"'));
  expect(text, contains('"bus"'));
  expect(text, contains('"remote"'));
});
```

- [ ] **Step 2: Implement**

```dart
final class AntigravityMcpCapability implements McpCapability {
  const AntigravityMcpCapability();

  @override
  Future<void> write({
    required Filesystem fs,
    required String configDir,
    required List<McpServerSpec> servers,
  }) => mergeMetadataMcpServers(
    fs: fs,
    configDir: configDir,
    metadataFileName: 'mcp_config.json',
    servers: servers,
  );
}
```

Register `mcp` on the tool definition and add it to `capabilities`.

- [ ] **Step 3: Run and commit**

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_resources_test.dart
git add client/lib/services/cli/antigravity client/test/services/cli/antigravity/antigravity_resources_test.dart
git commit -m "feat(antigravity): add MCP materialization"
```

---

### Task 9: Hooks writer and event matrix

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/hook_writer.dart`
- Modify: `client/lib/models/hook_event.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_hooks_test.dart`

**Interfaces:**
- Produces: `AntigravityHookWriter` with six native events and Antigravity
  `decision` JSON.

- [ ] **Step 1: Write the failing test**

```dart
test('renders hooks.json with a PreToolUse deny decision', () {
  const writer = AntigravityHookWriter();
  final result = writer.render(
    entries: [
      HookEntry(
        id: 'guard',
        source: HookSource.userLibrary,
        event: HookEvent.preToolUse,
        matcher: 'run_command',
        action: const CommandHookAction(command: 'echo blocked'),
        policy: HookPolicy.deny,
      ),
    ],
    ctx: const HookRenderContext(
      hooksDir: '/hooks',
      runner: null,
      glueBuilder: GlueScriptBuilder(),
    ),
  );
  final json = result.configFragments['hooks.json']! as String;
  expect(json, contains('"PreToolUse"'));
  expect(json, contains('"decision":"deny"'));
  expect(json, contains('"matcher":"run_command"'));
});
```

- [ ] **Step 2: Add matrix rows**

In `models/hook_event.dart#HookEventCapability.matrix`, add for
`CliTool.antigravity` only the keys that exist in `HookEvent`:

```dart
HookEvent.sessionStart: HookCliSupport(
  supported: true,
  nativeEvent: 'SessionStart',
),
HookEvent.userPromptSubmit: HookCliSupport(
  supported: true,
  approximate: true,
  nativeEvent: 'PreInvocation',
),
HookEvent.preToolUse: HookCliSupport(
  supported: true,
  nativeEvent: 'PreToolUse',
),
HookEvent.postToolUse: HookCliSupport(
  supported: true,
  nativeEvent: 'PostToolUse',
),
HookEvent.stop: HookCliSupport(
  supported: true,
  nativeEvent: 'Stop',
),
```

If `HookEvent` has no `stop` value, map `sessionEnd` → `Stop` instead.

- [ ] **Step 3: Implement the writer**

Use the same structure as `ClaudeFamilyHookWriter`, with these differences:

- `nativeEvent` reads the matrix for `CliTool.antigravity`.
- `supportsHttp = false`; HTTP entries add
  `hook_http_unsupported_<id>`.
- Decision JSON is `{"decision":"allow"}` / `{"decision":"deny","reason":"..."}`
  for intercepting events only.
- The config fragment key is `hooks.json`; the value is a JSON string shaped as:

```json
{
  "teampilot-<id>": {
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [
          {"type": "command", "command": "<script>", "timeout": 10}
        ]
      }
    ]
  }
}
```

- Reuse `ctx.glueBuilder.build(...)`, `GeneratedScript`, and the existing
  script-path contract. Native plugin hook actions add
  `hook_native_plugin_unsupported_<id>`.

- [ ] **Step 4: Register and run**

Add `hookWriter` to the tool definition/capabilities.

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_hooks_test.dart
git add client/lib/services/cli/antigravity client/lib/models/hook_event.dart client/test/services/cli/antigravity/antigravity_hooks_test.dart
git commit -m "feat(antigravity): add hooks writer"
```

---

### Task 10: Plugins and `plugin.json` projector

**Files:**
- Create: `client/lib/services/cli/registry/plugins/antigravity_plugin_projector.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/plugin.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_plugin_test.dart`

**Interfaces:**
- Produces: `AntigravityPluginProjector.project({fs, bundleDir, targetDir})` and
  `AntigravityPluginCapability`.

- [ ] **Step 1: Write the failing projector test**

```dart
test('projects a neutral bundle to plugin.json + components', () async {
  final fs = InMemoryFilesystem();
  await fs.ensureDir('/pool/pkg/.plugin');
  await fs.writeString('/pool/pkg/.plugin/plugin.json',
      '{"name":"demo","version":"1.0.0"}');
  await fs.ensureDir('/pool/pkg/skills/demo');
  await fs.writeString('/pool/pkg/skills/demo/SKILL.md',
      '---\nname: demo\ndescription: d\n---\n');
  await fs.ensureDir('/pool/pkg/agents');
  await fs.writeString('/pool/pkg/agents/a.md', '# a');
  await fs.writeString('/pool/pkg/.plugin/.mcp.json',
      '{"mcpServers":{"bus":{"command":"node","args":["bus.js"]}}}');

  await AntigravityPluginProjector.project(
    fs: fs,
    bundleDir: '/pool/pkg',
    targetDir: '/cfg/plugins/demo',
  );
  expect(await fs.readString('/cfg/plugins/demo/plugin.json'),
      contains('"demo"'));
  expect((await fs.stat('/cfg/plugins/demo/skills/demo/SKILL.md')).isFile,
      isTrue);
  expect(await fs.readString('/cfg/plugins/demo/mcp_config.json'),
      contains('bus'));
});
```

- [ ] **Step 2: Implement the projector**

```dart
final class AntigravityPluginProjector {
  static Future<void> project({
    required Filesystem fs,
    required String bundleDir,
    required String targetDir,
  }) async {
    final ctx = fs.pathContext;
    if ((await fs.stat(targetDir)).exists) {
      await fs.removeRecursive(targetDir);
    }
    await fs.ensureDir(targetDir);
    final manifest = await fs.readString(
          ctx.join(bundleDir, '.plugin', 'plugin.json'),
        ) ??
        await fs.readString(
          ctx.join(bundleDir, '.claude-plugin', 'plugin.json'),
        );
    if (manifest != null) {
      await fs.writeString(ctx.join(targetDir, 'plugin.json'), manifest);
    }
    for (final name in ['skills', 'agents', 'rules']) {
      final src = ctx.join(bundleDir, name);
      if ((await fs.stat(src)).isDirectory) {
        await fs.copyTree(
          source: src,
          destination: ctx.join(targetDir, name),
        );
      }
    }
    final mcp = await fs.readString(ctx.join(bundleDir, '.plugin', '.mcp.json')) ??
        await fs.readString(ctx.join(bundleDir, '.mcp.json'));
    if (mcp != null) {
      await fs.writeString(ctx.join(targetDir, 'mcp_config.json'), mcp);
    }
    final hooks =
        await fs.readString(ctx.join(bundleDir, '.plugin', 'hooks.json')) ??
            await fs.readString(ctx.join(bundleDir, 'hooks.json'));
    if (hooks != null) {
      await fs.writeString(ctx.join(targetDir, 'hooks.json'), hooks);
    }
  }
}
```

- [ ] **Step 3: Implement the capability**

```dart
final class AntigravityPluginCapability implements PluginCapability {
  const AntigravityPluginCapability();

  @override
  PluginRuntimeOwnership get runtimeOwnership => PluginRuntimeOwnership.teamPilot;

  @override
  PluginManifestPaths? get manifestPaths => neutralPluginManifestPaths;

  @override
  List<String> get memberPluginsSubpath => const ['plugins'];

  @override
  Set<PluginComponentKind> get supported => const {
    PluginComponentKind.skills,
    PluginComponentKind.agents,
    PluginComponentKind.hooks,
    PluginComponentKind.mcp,
    PluginComponentKind.rules,
  };

  @override
  Future<void> provision(PluginProvisionContext ctx) async {
    for (final id in ctx.enabledPluginIds) {
      final bundle = ctx.fs.pathContext.join(ctx.bundlePoolDir, id);
      if (!(await ctx.fs.stat(bundle)).isDirectory) continue;
      await AntigravityPluginProjector.project(
        fs: ctx.fs,
        bundleDir: bundle,
        targetDir: ctx.fs.pathContext.join(ctx.configDir, 'plugins', id),
      );
    }
  }

  @override
  bool get writesAssembledMcp => false;

  @override
  bool get consumesMarketplaces => true;

  @override
  bool get needsSharedPluginDepsBeforeReconcile => false;

  @override
  Future<void> seedSharedPluginDeps({
    required Filesystem homeFs,
    required String homeRoot,
  }) async {}

  @override
  String get pluginsSubdir => 'plugins';

  @override
  ResourceRepresentation get pluginsRepresentation =>
      ResourceRepresentation.linkedDirectory;
}
```

- [ ] **Step 4: Register and run**

Replace the no-op plugin capability on the tool and run:

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_plugin_test.dart
git add client/lib/services/cli/antigravity client/lib/services/cli/registry/plugins/antigravity_plugin_projector.dart client/test/services/cli/antigravity/antigravity_plugin_test.dart
git commit -m "feat(antigravity): add plugin projection"
```

---

### Task 11: Prompt/rules, workspace info, native commands

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/prompt.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/workspace_base_info.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/native_commands.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_prompt_test.dart`

**Interfaces:**
- Produces: `AntigravityPromptCapability` writing
  `<sessionToolDir>/home/.gemini/config/rules/teampilot.md`,
  `AntigravityWorkspaceBaseInfo`, `AntigravityNativeCommands`.

- [ ] **Step 1: Write the failing path test**

```dart
test('rules path lives under the fake HOME', () {
  expect(
    AntigravityPromptPaths.rulesPath('/runtime/sessions/s1/antigravity'),
    '/runtime/sessions/s1/antigravity/home/.gemini/config/rules/teampilot.md',
  );
});
```

- [ ] **Step 2: Implement**

```dart
abstract final class AntigravityPromptPaths {
  static String rulesPath(String sessionToolDir) => p.join(
    sessionToolDir,
    'home',
    '.gemini',
    'config',
    'rules',
    'teampilot.md',
  );
}

final class AntigravityPromptCapability implements PromptCapability {
  const AntigravityPromptCapability();

  @override
  Future<PromptMaterializeResult> materialize(
    PromptMaterializeContext ctx, {
    required PromptDocument document,
  }) async {
    final paths = ctx.paths;
    final scope = ctx.scope;
    if (paths == null || scope == null || document.content.isEmpty) {
      return const PromptMaterializeResult();
    }
    final toolDir = paths.sessionToolDir(
      scope.workspaceId,
      scope.sessionId,
      'antigravity',
      memberId: scope.memberId,
    );
    final path = AntigravityPromptPaths.rulesPath(toolDir);
    await paths.fs.ensureDir(paths.pathContext.dirname(path));
    await paths.fs.atomicWrite(path, '${document.content}\n');
    return const PromptMaterializeResult(written: true);
  }
}
```

`AntigravityWorkspaceBaseInfo` extends `WorkspaceBaseInfoCapabilityBase` and
returns `const []` from `buildWorkspaceAccessArgs` (ACP cwd is the workspace).
`AntigravityNativeCommands.commands` returns `const []` (ACP supplies native
commands through `available_commands_update`).

- [ ] **Step 3: Register and run**

Add `prompt`, `workspaceBaseInfo`, and `nativeCommands` to the tool. Replace the
default `workspaceBaseInfo` if it is a no-op.

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_prompt_test.dart
git add client/lib/services/cli/antigravity client/test/services/cli/antigravity/antigravity_prompt_test.dart
git commit -m "feat(antigravity): add rules, workspace info, and native commands"
```

---

### Task 12: Headless capability

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/headless.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_headless_test.dart`

**Interfaces:**
- Produces: `AntigravityHeadlessCapability` with `-p`, stream-json, model,
  effort, full-access flags.

- [ ] **Step 1: Write the failing argv test**

```dart
test('builds agy headless argv', () {
  const cap = AntigravityHeadlessCapability();
  const ctx = CliHeadlessLaunchContext(
    prompt: 'hi',
    model: 'gemini-3.8-flash-medium',
    effort: 'high',
    configDir: '/cfg',
    stream: true,
    securityPolicy: LaunchSecurityPolicy.fullAccess,
  );
  final args = cap
      .buildHeadlessLaunchArgs(ctx)
      .expand((contribution) => contribution.args)
      .toList();
  expect(args, containsAllInOrder(['-p', 'hi']));
  expect(args, containsAllInOrder(['--model', 'gemini-3.8-flash-medium']));
  expect(args, containsAllInOrder(['--effort', 'high']));
  expect(args, contains('--dangerously-skip-permissions'));
  expect(args, containsAllInOrder(['--output-format', 'stream-json']));
});
```

- [ ] **Step 2: Implement**

```dart
final class AntigravityHeadlessCapability implements HeadlessCapability {
  const AntigravityHeadlessCapability();

  @override
  String get executable => 'agy';

  @override
  bool get isSupported => true;

  @override
  bool get supportsStreaming => true;

  @override
  bool get supportsPromptStdin => true;

  @override
  Map<String, String> buildEnvironment(HeadlessLaunchContext context) => {
    'HOME': '${context.configDir}/home',
    'USERPROFILE': '${context.configDir}/home',
    'GEMINI_HOME': '${context.configDir}/home/.gemini',
  };

  @override
  List<HeadlessConfigFile> configFiles(HeadlessLaunchContext ctx) => const [];

  @override
  Iterable<CliLaunchArgContribution> buildHeadlessLaunchArgs(
    CliHeadlessLaunchContext context,
  ) => [
    CliLaunchArgContribution(
      key: 'antigravity-headless',
      phase: LaunchArgPhase.command,
      args: [
        '-p',
        context.prompt,
        if (context.model.isNotEmpty) ...['--model', context.model],
        if (context.effort.isNotEmpty) ...['--effort', context.effort],
        if (context.securityPolicy == LaunchSecurityPolicy.fullAccess)
          '--dangerously-skip-permissions',
        if (context.stream) ...['--output-format', 'stream-json'],
        if (context.expectJson && !context.stream) ...['--output-format', 'json'],
      ],
    ),
  ];

  @override
  String? streamResultText(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map || decoded['event'] != 'result') return null;
    final result = decoded['result'];
    return result is Map ? result['response']?.toString() : null;
  }

  @override
  String extractText(ProcessResult result) {
    final text = result.stdout.toString().trim();
    if (text.isEmpty) return '';
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['response'] is String) {
        return decoded['response'] as String;
      }
    } catch (_) {}
    return text;
  }

  @override
  Future<HeadlessProvisionResult> provision(
    HeadlessProvisionContext ctx,
  ) async => const HeadlessProvisionResult();
}
```

If `CliLaunchArgContribution` requires `exclusiveGroup` or other named
parameters, add the defaults used by existing headless capabilities.

- [ ] **Step 3: Register and run**

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_headless_test.dart
git add client/lib/services/cli/antigravity client/test/services/cli/antigravity/antigravity_headless_test.dart
git commit -m "feat(antigravity): add headless runs"
```

---

### Task 13: History stub and tool-call resolvers

**Files:**
- Create: `client/lib/services/cli/antigravity/capabilities/history/ai_history_capability.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/tool_call_resolvers.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/cli/antigravity/antigravity_history_test.dart`

**Interfaces:**
- Produces: `AntigravityAiHistoryCapability` stub with non-null resolvers.

- [ ] **Step 1: Write the failing test**

```dart
test('history is ACP-owned and exposes resolvers', () {
  const cap = AntigravityAiHistoryCapability();
  expect(cap.adapter.id, 'antigravity');
  expect(cap.tailFallbackPrefix, 'antigravity');
  expect(cap.editResolver, isNotNull);
  expect(cap.shellResolver, isNotNull);
  expect(cap.categoryResolver, isNotNull);
});
```

- [ ] **Step 2: Implement**

Copy `codebuddy/capabilities/history/ai_history_capability.dart`, rename to
`AntigravityAiHistoryCapability` / `AntigravityAiTranscriptAdapter`, and change:

- `adapter.id` / `tailFallbackPrefix` → `'antigravity'`.
- `sessionEnv` → `{'HOME': toolRoot}` (the isolated home root is the tool root
  in the launch context).
- `subagentToolNames` → `const {'invoke_subagent'}`.
- Resolvers → `AntigravityToolCallResolvers.instance`.

Create `AntigravityToolCallResolvers` by copying
`cursor/capabilities/tool_call_resolvers.dart` (it already uses the
`Configurable*` constructors) and extending the key sets with:
`run_command`, `view_file`, `write_to_file`, `replace_file_content`,
`multi_replace_file_content`, `list_dir`, `find_by_name`, `grep_search`,
`search_web`, `read_url_content`, `invoke_subagent`, `send_message`,
`manage_task`, `schedule`, `ask_question`, `generate_image`. Keep the shared
`SharedToolCallResolvers` as the base; append Antigravity keys rather than
replacing shared behavior.

- [ ] **Step 3: Register and run**

```bash
cd client
dart run tool/run_tests.dart test/services/cli/antigravity/antigravity_history_test.dart
git add client/lib/services/cli/antigravity client/test/services/cli/antigravity/antigravity_history_test.dart
git commit -m "feat(antigravity): add ACP-owned history stub and tool resolvers"
```

---

### Task 14: ACP usage collector + Antigravity usage

**Files:**
- Create: `client/lib/services/acp/acp_usage.dart`
- Modify: `client/lib/services/acp/acp_session.dart`
- Modify: `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- Create: `client/lib/services/cli/antigravity/capabilities/usage.dart`
- Modify: `client/lib/services/cli/antigravity/antigravity_tool.dart`
- Test: `client/test/services/acp/acp_usage_test.dart`
- Test: `client/test/services/cli/antigravity/antigravity_usage_test.dart`

**Interfaces:**
- Produces: `AcpUsageUpdate` chat-layer variant, `AcpUsageRecord`,
  `AcpUsageRecorder.append`, and `AntigravitySessionUsageCapability`.

- [ ] **Step 1: Write the failing mapping test**

```dart
test('maps usage_update into a record', () {
  final record = AcpUsageRecord.fromUpdate(
    sessionId: 's1',
    used: 120,
    size: 1000,
  );
  expect(record.used, 120);
  expect(record.size, 1000);
  expect(record.totalTokens, 120);
});
```

- [ ] **Step 2: Add the chat-layer variant and recorder**

In `acp_session.dart`:

```dart
final class AcpUsageUpdate extends AcpSessionUpdate {
  const AcpUsageUpdate({this.used, this.size, this.cost});
  final int? used;
  final int? size;
  final acpd.Cost? cost;
}
```

In `_mapUpdate`, replace the `default` comment path for usage:

```dart
case acpd.UsageSessionUpdate update:
  return AcpUsageUpdate(
    used: update.used,
    size: update.size,
    cost: update.cost,
  );
```

`acp_usage.dart`:

```dart
final class AcpUsageRecord {
  const AcpUsageRecord({
    required this.sessionId,
    required this.used,
    required this.size,
    required this.sequence,
    this.cost,
  });

  factory AcpUsageRecord.fromUpdate({
    required String sessionId,
    required int? used,
    required int? size,
    Object? cost,
  }) => AcpUsageRecord(
    sessionId: sessionId,
    used: used ?? 0,
    size: size ?? 0,
    sequence: DateTime.now().microsecondsSinceEpoch,
    cost: cost,
  );

  final String sessionId;
  final int used;
  final int size;
  final int sequence;
  final Object? cost;
  int get totalTokens => used;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'used': used,
    'size': size,
    'sequence': sequence,
    if (cost != null) 'cost': cost,
  };
}

final class AcpUsageRecorder {
  const AcpUsageRecorder(this.fs);
  final Filesystem fs;

  Future<void> append(String sessionToolDir, AcpUsageUpdate update) async {
    final path = fs.pathContext.join(sessionToolDir, 'acp-usage.jsonl');
    final record = AcpUsageRecord.fromUpdate(
      sessionId: fs.pathContext.basename(sessionToolDir),
      used: update.used,
      size: update.size,
      cost: update.cost,
    );
    await fs.ensureDir(fs.pathContext.dirname(path));
    await fs.appendString(path, '${jsonEncode(record.toJson())}\n');
  }
}
```

- [ ] **Step 3: Persist from the cubit**

Store `sessionToolDir` on `AcpChatRuntimeCubit.start`, then in `_onUpdate`:

```dart
if (update is AcpUsageUpdate) {
  await AcpUsageRecorder(_runtime.fs).append(_sessionToolDir!, update);
  return;
}
```

If `AcpSessionRuntimeApi` does not expose `fs`, inject an `AcpUsageRecorder`
into the cubit constructor from the attach site (preferred).

- [ ] **Step 4: Implement the capability**

`AntigravitySessionUsageCapability`:

- `discoverUsageSources` returns `<sessionToolDir>/acp-usage.jsonl`.
- `scanUsageSource` reads JSONL lines. Probe 1.4.3: `used` is the per-turn
  context delta, not cumulative and not output tokens. Map it to the
  input/context token field, record `size` as the context window, and do not
  synthesize output tokens or a cost when `cost` is absent. Emit
  `SessionUsageEvent` with `cli: CliTool.antigravity`,
  `requestId: '<sessionId>:<sequence>'`.
- Register `sessionUsage` on the tool.

- [ ] **Step 5: Run and commit**

```bash
cd client
dart run tool/run_tests.dart test/services/acp/acp_usage_test.dart test/services/cli/antigravity/antigravity_usage_test.dart
git add client/lib/services/acp client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart \
  client/lib/services/cli/antigravity client/test/services/acp client/test/services/cli/antigravity
git commit -m "feat(acp): capture usage_update for Antigravity"
```

---

### Task 15: UI wiring — l10n, icons, labels, bootstrap, readiness

**Files:**
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Modify: `client/lib/l10n/l10n_extensions.dart`
- Modify: `client/lib/widgets/cli/cli_brand_icon.dart`
- Modify: `client/lib/widgets/app_provider/provider_credential_messages.dart`
- Modify: `client/lib/widgets/app_provider/provider_credential_action_bar.dart`
- Modify: `client/lib/pages/usage/usage_format.dart`
- Modify: `client/lib/services/storage/workspace_cli_cache.dart`
- Modify: `client/lib/app/app_shell.dart`
- Add: `client/assets/providers/antigravity.svg`
- Test: `client/test/widgets/app_provider/provider_icon_registry_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces: no compile-time `CliTool` switch misses; Antigravity readiness and
  brand icon work.

- [ ] **Step 1: Add l10n keys**

```json
"antigravitySignInHint": "Sign in with the Antigravity CLI. The account is shared with other Antigravity sessions on this machine.",
"antigravityAdapterMissing": "The Antigravity ACP adapter is not installed.",
"antigravityStarting": "Starting Antigravity…"
```

Add the Chinese equivalents to `app_zh.arb`. `appProviderToolAntigravity` was
already added in Task 6.

- [ ] **Step 2: Polish exhaustive switches and icon**

Task 6 already added minimal entries so the tree compiles. Replace them with
final copy/assets:

- `cli_brand_icon.dart`: point `'antigravity'` at the new SVG and regenerate
  the provider icon catalog.
- `usage_format.dart`: final label and brand color.
- `provider_credential_messages.dart` / `provider_credential_action_bar.dart`:
  final sign-in/success/failure copy.
- `l10n_extensions.dart` / `workspace_cli_cache.dart`: verify the Task 6
  entries are still correct.

- [ ] **Step 3: Finish the bootstrap wiring**

`app_shell.dart` already has the entry from Task 7; verify it passes a real
`BinaryArchiveInstaller` built from the app's `RemoteDownloader` and that the
`CliInstallJobRunner` gets the adapter resolver from Task 5.

- [ ] **Step 4: Run analyze + icon test**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/widgets/app_provider/provider_icon_registry_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/l10n client/lib/widgets client/lib/pages/usage/usage_format.dart \
  client/lib/services/storage/workspace_cli_cache.dart client/lib/app/app_shell.dart \
  client/assets/providers client/test/widgets/app_provider/provider_icon_registry_test.dart
git commit -m "feat(antigravity): wire UI labels, icons, and bootstrap"
```

---

### Task 16: Session gating, docs, integration smoke, full verification

**Files:**
- Test: `client/test/services/chat/launch/session/antigravity_acp_gate_test.dart`
- Create: `client/test/integration/antigravity_acp_local_smoke_test.dart`
- Create: `docs/cli-formats/antigravity.md`
- Modify: `docs/cli-formats/README.md`, `docs/cli-formats/tool-layer-coverage.md`,
  `docs/cli-formats/hooks.md`, `docs/cli-architecture.md`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: verified gating, docs, and a skipped-when-absent smoke.

- [ ] **Step 1: Add the gating test**

Use the existing helpers in `app_session.dart` and
`acp_compose_permission.dart`:

```dart
test('personal desktop sessions infer ACP for Antigravity', () {
  final session = AppSession.forTesting(cli: CliTool.antigravity, team: '');
  expect(session.acp, isTrue);
});

test('Android rejects personal ACP for Antigravity', () {
  expect(willLaunchPersonalAcp(cli: CliTool.antigravity, isAndroid: true), isFalse);
});
```

If `AppSession.forTesting` does not exist, use the existing `AppSession`
constructor used by `session_provisional_builder_test.dart`.

- [ ] **Step 2: Add the integration smoke**

```dart
@Tags(['integration'])
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('antigravity ACP initialize + session/new + one prompt', () async {
    final adapter = await locateInstalledAntigravityAdapter();
    if (adapter == null) {
      markTestSkipped('agy_acp_server not installed');
      return;
    }
    // Mirror codebuddy_acp_local_smoke_test.dart with
    // productionAcpSpawner + AcpSessionRuntime.
    // 1. initialize
    // 2. session/new with cwd
    // 3. session/prompt 'Reply with exactly: ok'
    // 4. expect a message chunk containing 'ok'
  });
}
```

- [ ] **Step 3: Write docs**

`docs/cli-formats/antigravity.md` must include:

- ACP-only launch (`agy_acp_server`), no PTY.
- Tool names and edit/file/shell key mapping.
- Hook events table.
- Config paths (`~/.gemini/config/*`, `~/.gemini/antigravity-cli/*`).
- Usage source (`acp-usage.jsonl`, headless `result.usage`).
- Known limits (cold start, arm64, model on `session/new`).

Update `docs/cli-formats/README.md`, `tool-layer-coverage.md`,
`hooks.md`, and `docs/cli-architecture.md`.

- [ ] **Step 4: Run focused tests**

```bash
cd client
flutter analyze --no-fatal-infos --no-fatal-warnings
dart run tool/run_tests.dart test/services/cli/antigravity test/services/acp test/services/install
```

- [ ] **Step 5: Run the full suite once**

```bash
cd client && dart run tool/run_tests.dart
```

Do not claim completion until it is green.

- [ ] **Step 6: Commit**

```bash
git add client/test client/lib docs
git commit -m "test(antigravity): add gating, smoke, and docs"
```

---

## Self-Review

- **Spec coverage:** probe (1), adapter abstraction/install (2–4), readiness
  (5), core ACP slice (6), provider/auth (7), skills/MCP (8), hooks (9),
  plugins (10), prompt/workspace (11), headless (12), history (13), usage (14),
  UI (15), gating/docs/smoke (16).
- **Placeholder scan:** no TBD/TODO; each task has a concrete command or code
  step.
- **Type consistency:** the neutral interface uses `adapterJobTarget` while
  Claude/Codex keep their static `jobTarget`; `AcpSettingsCapability` stores the
  neutral type; `CliInstallerService.installAdapter` takes the neutral type.
- **Known execution risk:** some constructor field names (`PromptMaterializeContext`,
  `HookRenderContext`, `CliExecutablePathRowSpec`) are shown with the current
  signatures; the implementer must run `flutter analyze` after each task and
  adapt to the exact signature rather than inventing a parallel API.
