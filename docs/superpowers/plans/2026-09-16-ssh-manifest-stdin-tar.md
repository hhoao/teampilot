# SSH Manifest stdin + Overlay Tar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SSH launch flush sends scripts and file overlays on CHANNEL_DATA stdin so off-home Cursor sessions no longer die on `exec(600+ heredocs)`.

**Architecture:** `SSHClient.runWithResult` gains optional stdin (write + EOF). Storage-plane `runOnStorageWithStdin` uses that for `bash -s` scripts and for a short `gzip -dc | tar -x -C <workRoot>` extract. Off-home manifests are split into mutation-script vs overlay-tar epochs relative to `appDataRoot`. Same-host flushes keep the small `cp`/`ln` script, now also via `bash -s`. Probe-evict is skipped while another storage op is in flight. Personal SSH reconnect treats `ConnectShellResult.failed` as a failed reconnect.

**Tech Stack:** Dart 3.8 / Flutter (TeamPilot `client/`), vendored `dartssh2`, `package:archive` 4.2 (`TarEncoder`, `GZipEncoder`, `ArchiveFile`), existing `SshClientFactory` storage pool.

## Global Constraints

- Never put file bodies or large scripts in the SSH `exec` command string (max ~1KB command).
- Scripts: `bash -s` + stdin. Tar extract: exec the gzip|tar pipeline; stdin is the gzip stream (not `bash -s`).
- Overlay tar members are relative to `symlinkProjectionRoot` / work `appDataRoot`; reject `..` and absolute members.
- Do not pack the entire TeamPilot home; only this flush's overlay.
- Copy trees/files into the tar as **raw bytes** from `sourceFs.readBytes` (no `utf8.decode(allowMalformed: true)`).
- `cd client && dart run tool/run_tests.dart …` for app tests — never `flutter test` in `client/`.
- dartssh2 package tests: `cd client/packages/dartssh2 && dart test <file>`.
- Services files stay near the ~600 line soft limit; put overlay/epoch logic in new files, do not grow `manifest_executor.dart` with tar encoding.
- Do not commit unless the user asks; skip commit steps during execution if they have not.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/packages/dartssh2/lib/src/ssh_client.dart` | Optional `stdin` on `runWithResult`; write then close stdin |
| `client/packages/dartssh2/test/src/ssh_client_run_with_result_test.dart` | Stdin bytes appear as CHANNEL_DATA; EOF still completes |
| `client/lib/services/ssh/ssh_client_factory.dart` | `runOnStorageWithStdin`; skip ping probe when `_inFlight > 1` |
| `client/lib/services/launch/work_plane_script_runner.dart` | `bash -s` via stdin; `runStdinCommand` for tar pipeline |
| `client/lib/services/launch/manifest_ssh_overlay.dart` | Path sandbox, `Archive` overlay, gzip, extract command |
| `client/lib/services/launch/manifest_ssh_flush_plan.dart` | Ordered epochs: mutation script vs overlay tar |
| `client/lib/services/launch/manifest_executor.dart` | SSH flush executes the plan; same-host still uses `_buildApplyScript` |
| `client/lib/services/launch/session_ssh_profile_reconnect.dart` | Surface `ConnectShellResult.failed`/`aborted` as throw |
| Tests listed per task | |

---

### Task 1: dartssh2 `runWithResult` stdin

**Files:**
- Modify: `client/packages/dartssh2/lib/src/ssh_client.dart` (`runWithResult`)
- Test: `client/packages/dartssh2/test/src/ssh_client_run_with_result_test.dart`

**Interfaces:**
- Consumes: existing `execute` / `SSHSession.stdin`
- Produces: `Future<SSHRunResult> runWithResult(String command, {bool runInPty = false, bool stdout = true, bool stderr = true, Map<String, String>? environment, List<int>? stdin})`

- [ ] **Step 1: Write the failing test**

Add inside `group('SSHClient.runWithResult'` in `ssh_client_run_with_result_test.dart`:

```dart
test('writes stdin then closes it before waiting for exit', () async {
  final harness = _SessionHarness();
  final client = _TestSSHClient(() async => harness.session);
  final stdin = Uint8List.fromList(utf8.encode('hello-stdin'));

  final resultFuture = client.runWithResult('bash -s', stdin: stdin);
  await Future<void>.delayed(Duration.zero);

  final data = harness.sentMessages.whereType<SSH_Message_Channel_Data>();
  expect(
    data.any((m) => utf8.decode(m.data) == 'hello-stdin'),
    isTrue,
  );

  harness.sendExitStatus(0);
  harness.close();
  final result = await resultFuture;
  expect(result.exitCode, 0);

  harness.dispose();
  client.close();
});
```

If `SSH_Message_Channel_Data` field is not `data`, match the existing `sendStdout` constructor in the same file.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client/packages/dartssh2 && dart test test/src/ssh_client_run_with_result_test.dart --name "writes stdin"`

Expected: FAIL (named argument `stdin` isn't defined).

- [ ] **Step 3: Write minimal implementation**

In `runWithResult`, after attaching stdout/stderr listeners and **before** `Future.wait`:

```dart
if (stdin != null && stdin.isNotEmpty) {
  session.write(Uint8List.fromList(stdin));
}
await session.stdin.close();
```

Keep the rest of the method unchanged. Closing stdin even when `stdin` is null is required so `bash -s` / `gzip -dc` see EOF.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client/packages/dartssh2 && dart test test/src/ssh_client_run_with_result_test.dart`

Expected: PASS (including existing `runWithResult` cases).

- [ ] **Step 5: Commit** (only if the user asked)

```bash
git add client/packages/dartssh2/lib/src/ssh_client.dart \
  client/packages/dartssh2/test/src/ssh_client_run_with_result_test.dart
git commit -m "$(cat <<'EOF'
fix(dartssh2): send runWithResult payload on session stdin

EOF
)"
```

---

### Task 2: Storage `runOnStorageWithStdin` + `bash -s` scripts

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart`
- Modify: `client/lib/services/launch/work_plane_script_runner.dart`
- Test: `client/test/services/launch/work_plane_script_runner_test.dart`
- Modify: `client/test/services/cli/registry/capabilities/cli_session_capability_test.dart` (`_RecordingRunner`)
- Modify fake `runWithResult` in `work_plane_script_runner_test.dart` and `manifest_executor_ssh_test.dart` to accept `stdin`

**Interfaces:**
- Consumes: `SSHClient.runWithResult(..., stdin: …)` from Task 1
- Produces:
  - `SshClientFactory.runOnStorageWithStdin(SshProfile profile, String command, {required List<int> stdin, Duration timeout = SshStorageIo.provisionPhaseTimeout, bool stderr = true}) → Future<SSHRunResult>`
  - `WorkPlaneScriptRunner.runStdinCommand({required String command, required List<int> stdin, required String operation, Duration? timeout})`
  - `SshWorkPlaneScriptRunner.runScript` calls `runOnStorageWithStdin(profile, 'bash -s', stdin: utf8.encode(script))`

- [ ] **Step 1: Write the failing test**

In `work_plane_script_runner_test.dart`, change `_RunnableClient.runWithResult` to take `List<int>? stdin` and record both command and stdin. Replace the first test expectation:

```dart
test('SshWorkPlaneScriptRunner sends script on stdin not exec command', () async {
  String? ran;
  List<int>? stdin;
  // … same factory setup, onRun: (command, bytes) { ran = command; stdin = bytes; }

  await runner.runScript('echo hi', operation: 'test-op');

  expect(ran, 'bash -s');
  expect(utf8.decode(stdin!), 'echo hi');
  expect(ran, isNot(contains('echo hi')));
});

test('SshWorkPlaneScriptRunner.runStdinCommand keeps short exec command', () async {
  String? ran;
  List<int>? stdin;
  // … 
  await runner.runStdinCommand(
    command: "gzip -dc | tar -x -C '/tmp/root'",
    stdin: Uint8List.fromList([1, 2, 3]),
    operation: 'Launch overlay extract',
  );
  expect(ran, "gzip -dc | tar -x -C '/tmp/root'");
  expect(stdin, [1, 2, 3]);
});
```

Update `_RecordingRunner` with an empty `runStdinCommand` so it still implements the interface.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_plane_script_runner_test.dart`

Expected: FAIL (`runOnStorageWithStdin` / `runStdinCommand` missing, or script still equals `echo hi`).

- [ ] **Step 3: Write minimal implementation**

`ssh_client_factory.dart` next to `runOnStorage`:

```dart
static const maxExecCommandBytes = 1024;

Future<SSHRunResult> runOnStorageWithStdin(
  SshProfile profile,
  String command, {
  required List<int> stdin,
  Duration timeout = SshStorageIo.provisionPhaseTimeout,
  bool stderr = true,
}) {
  if (utf8.encode(command).length > maxExecCommandBytes) {
    throw StateError(
      'storage exec command exceeds $maxExecCommandBytes bytes',
    );
  }
  return _tracked(profile.id, () async {
    final client = await clientForStorage(profile);
    try {
      return await SshStorageIo.awaitOrThrow(
        client.runWithResult(command, stderr: stderr, stdin: stdin),
        timeout: timeout,
        operation: 'storage exec stdin',
      );
    } on TimeoutException {
      _evictProfile(
        profile.id,
        closePooled: true,
        reason: SshTransportCloseReason.transportError,
      );
      rethrow;
    }
  });
}
```

`work_plane_script_runner.dart`:

```dart
abstract interface class WorkPlaneScriptRunner {
  Future<void> runScript(
    String script, {
    required String operation,
    Duration? timeout,
  });

  Future<void> runStdinCommand({
    required String command,
    required List<int> stdin,
    required String operation,
    Duration? timeout,
  });
}
```

`SshWorkPlaneScriptRunner.runScript`:

```dart
final result = await sshClientFactory.runOnStorageWithStdin(
  profile,
  'bash -s',
  stdin: utf8.encode(script),
  timeout: timeout ?? SshStorageIo.provisionPhaseTimeout,
);
```

`runStdinCommand`: same helper as `runScript` but `command`/`stdin` passed through; on `sshRunFailed` throw `StateError('$operation failed on ${profile.host}: $detail')`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/work_plane_script_runner_test.dart test/services/cli/registry/capabilities/cli_session_capability_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

---

### Task 3: Skip keepalive probe while another storage op is in flight

**Files:**
- Modify: `client/lib/services/ssh/ssh_client_factory.dart` (`clientForStorage`)
- Test: `client/test/services/ssh/ssh_client_factory_pool_test.dart`

**Interfaces:**
- Consumes: `_inFlight` / `_tracked` already on the factory
- Produces: `clientForStorage` skips `_probeStorageClient` when `(_inFlight[profile.id] ?? 0) > 1`

- [ ] **Step 1: Write the failing test**

```dart
test('clientForStorage skips probe while another storage op is in flight', () async {
  var pingCount = 0;
  var createCount = 0;
  final gate = Completer<void>();
  late final _BlockingRunClient client;
  final factory = SshClientFactory(
    credentialStore: InMemorySshCredentialStore(),
    knownHostRepository: InMemorySshKnownHostRepository(),
    connector: (profile, {timeout = const Duration(seconds: 10)}) async {
      createCount += 1;
      return client;
    },
  );
  const profile = SshProfile(
    id: 'p1', name: 'dev', host: 'example.com', username: 'alice',
  );
  client = _BlockingRunClient(gate.future, [])
    ..onPing = () {
      pingCount += 1;
      throw StateError('probe should not run');
    };

  await factory.clientForStorage(profile);
  pingCount = 0;
  final op = factory.runOnStorageWithStdin(
    profile,
    'bash -s',
    stdin: utf8.encode('sleep'),
  );
  await Future<void>.delayed(Duration.zero);

  final second = await factory.clientForStorage(profile);
  expect(identical(second, client), isTrue);
  expect(createCount, 1);
  expect(pingCount, 0);

  gate.complete();
  await op;
});
```

Extend `_BlockingRunClient` (same file) with `void Function()? onPing` and `ping()` calling it; default `ping` no-op so existing drain tests stay green. If `_BlockingRunClient` has no `runWithResult` stdin yet, add the optional argument and ignore it.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_client_factory_pool_test.dart --plain-name "skips probe"`

Expected: FAIL (probe still runs and throws / createCount becomes 2).

- [ ] **Step 3: Write minimal implementation**

In `clientForStorage`, when reusing a live cached client:

```dart
final inFlight = _inFlight[profile.id] ?? 0;
final skipProbe = !probeCached || inFlight > 1;
if (skipProbe || await _probeStorageClient(cached.client)) {
  return cached.client;
}
```

Do not evict on a skipped probe. Existing `inFlight == 1` (the caller itself) may still probe.

- [ ] **Step 4: Run the pool tests**

Run: `cd client && dart run tool/run_tests.dart test/services/ssh/ssh_client_factory_pool_test.dart`

Expected: PASS, including `rebuilds when keepalive probe fails`.

- [ ] **Step 5: Commit** (only if the user asked)

---

### Task 4: Overlay tar + path sandbox (pure)

**Files:**
- Create: `client/lib/services/launch/manifest_ssh_overlay.dart`
- Test: `client/test/services/launch/manifest_ssh_overlay_test.dart`

**Interfaces:**
- Consumes: `package:archive` `Archive`, `ArchiveFile`, `ArchiveFile.symlink`, `TarEncoder`, `GZipEncoder`
- Produces:
  - `String? manifestOverlayRelativePath({required String absolutePath, required String workRoot, required p.Context pathContext})`
  - `Uint8List encodeLaunchOverlayGzip(Archive archive)`
  - `String launchOverlayExtractCommand(String workRoot)` → `gzip -dc | tar -x -C <quoted>`
  - `void addOverlayFile(Archive archive, {required String relativePath, required List<int> bytes})`
  - `void addOverlaySymlink(Archive archive, {required String relativePath, required String target})`
  - `void addOverlayDir(Archive archive, {required String relativePath})`

- [ ] **Step 1: Write the failing test**

```dart
void main() {
  final ctx = p.Context(style: p.Style.posix);
  const root = '/home/u/.local/share/com.hhoa.teampilot';

  test('relative path under work root', () {
    expect(
      manifestOverlayRelativePath(
        absolutePath: '$root/sessions/s1/a.json',
        workRoot: root,
        pathContext: ctx,
      ),
      'sessions/s1/a.json',
    );
  });

  test('rejects escape and absolute members', () {
    expect(
      manifestOverlayRelativePath(
        absolutePath: '/etc/passwd',
        workRoot: root,
        pathContext: ctx,
      ),
      isNull,
    );
    expect(
      manifestOverlayRelativePath(
        absolutePath: '$root/../outside',
        workRoot: root,
        pathContext: ctx,
      ),
      isNull,
    );
  });

  test('gzip tar round-trips file symlink and dir', () {
    final archive = Archive();
    addOverlayFile(archive, relativePath: 'a.txt', bytes: utf8.encode('hi'));
    addOverlaySymlink(archive, relativePath: 'link', target: '/opt/x');
    addOverlayDir(archive, relativePath: 'empty');
    final gz = encodeLaunchOverlayGzip(archive);
    expect(gz.length, greaterThan(32));
    final tar = GZipDecoder().decodeBytes(gz);
    final decoded = TarDecoder().decodeBytes(tar);
    expect(decoded.files.map((f) => f.name), containsAll(['a.txt', 'link', 'empty']));
    expect(decoded.findFile('link')!.symbolicLink, '/opt/x');
    expect(utf8.decode(decoded.findFile('a.txt')!.content as List<int>), 'hi');
  });

  test('extract command is short pipeline not bash -s', () {
    final cmd = launchOverlayExtractCommand(root);
    expect(cmd.startsWith('gzip -dc | tar -x -C '), isTrue);
    expect(cmd, contains("'${root}'"));
    expect(utf8.encode(cmd).length, lessThan(1024));
    expect(cmd, isNot(contains('bash -s')));
  });
}
```

Use `ArchiveFile` APIs actually present in archive 4.2 (`findFile` / `content` — adjust to `getContent()?.toUint8List()` if needed).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_ssh_overlay_test.dart`

Expected: FAIL (library missing).

- [ ] **Step 3: Write minimal implementation**

`manifest_ssh_overlay.dart`:

- Normalize `workRoot` and `absolutePath` with `pathContext.normalize`.
- Relative via `pathContext.relative`; return null unless `pathContext.isWithin(root, path) || path == root`.
- Reject any relative that is empty, starts with `/`, or has `..` segments.
- Quote workRoot like existing `_shellQuote`: `"'${value.replaceAll("'", "'\"'\"'")}'"`.
- Encode: `GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive))`.
- Directory entries: `ArchiveFile(relativePath, 0, const <int>[])` with `isFile = false` (set after construct if that's the 4.2 pattern), or equivalent `ArchiveFile` directory helper.

Long names (>100 chars) are handled by `TarEncoder` GNU `@LongLink` — do not add a second scheme.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_ssh_overlay_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

---

### Task 5: Epoch flush plan (unexpanded manifest)

**Files:**
- Create: `client/lib/services/launch/manifest_ssh_flush_plan.dart`
- Test: `client/test/services/launch/manifest_ssh_flush_plan_test.dart`

**Interfaces:**
- Consumes: `LaunchManifest`, `Filesystem.readBytes` / `listDirRecursive` / `lstat`, Task 4 overlay helpers, existing `ManifestExecutor.debugBuildApplyScript` quoting/script ops for mutations only
- Produces:
  - `enum ManifestSshEpochKind { script, tar }`
  - `class ManifestSshEpoch { kind; String? script; Uint8List? gzipTar; String? extractCommand; }`
  - `Future<List<ManifestSshEpoch>> buildManifestSshFlushPlan({required LaunchManifest manifest, required Filesystem sourceFs, required String workRoot, required bool sameHost})`

Same-host (`sameHost: true`): one script epoch from today's `_buildApplyScript` (mkdir/ln/cp/rm), no tar.

Off-home: walk **unexpanded** entries in order:

- Payload (buffer overlay): `ensureDir`, `writeFile`, in-root `symlink`, `copyFile`/`copyTree` (read bytes from `sourceFs`).
- Mutation (buffer script): `removeRecursive`, `rename`.
- Out-of-root symlink: treat as payload file/tree copy (raw bytes), not a tar symlink.
- Before a tar epoch that contains symlink members, prepend `rm -rf -- <linkPath>` lines (same leftover-dir fix as today's apply script).
- On kind switch, flush the current buffer as an epoch; after the loop flush both.
- Payload path outside `workRoot`: those `writeFile`s go into a `bash -s` script epoch as heredocs (reuse `_buildApplyScript` on a tiny manifest), not the tar.

- [ ] **Step 1: Write the failing tests**

```dart
test('same-host plan is one cp script epoch', () async {
  final fs = InMemoryFilesystem();
  final manifest = LaunchManifest()
    ..copyTree(source: '/src/tree', destination: '/dst/tree');
  final epochs = await buildManifestSshFlushPlan(
    manifest: manifest,
    sourceFs: fs,
    workRoot: '/dst',
    sameHost: true,
  );
  expect(epochs, hasLength(1));
  expect(epochs.single.kind, ManifestSshEpochKind.script);
  expect(epochs.single.script, contains("cp -R -- '/src/tree/.' '/dst/tree'"));
  expect(epochs.single.gzipTar, isNull);
});

test('off-home copyTree becomes tar bytes not cat heredoc', () async {
  final fs = InMemoryFilesystem();
  await fs.writeBytes('/home/src/bin.dat', [0, 1, 255]);
  final root = '/work/root';
  final manifest = LaunchManifest()
    ..copyTree(source: '/home/src', destination: '$root/pool/bin');
  final epochs = await buildManifestSshFlushPlan(
    manifest: manifest,
    sourceFs: fs,
    workRoot: root,
    sameHost: false,
  );
  expect(epochs, hasLength(1));
  expect(epochs.single.kind, ManifestSshEpochKind.tar);
  expect(epochs.single.extractCommand, contains('gzip -dc | tar -x -C'));
  final tar = GZipDecoder().decodeBytes(epochs.single.gzipTar!);
  final decoded = TarDecoder().decodeBytes(tar);
  final file = decoded.findFile('pool/bin/bin.dat')!;
  expect(file.content as List<int>, [0, 1, 255]);
});

test('write then remove keeps tar then script order', () async {
  final fs = InMemoryFilesystem();
  const root = '/work/root';
  final manifest = LaunchManifest()
    ..writeFile('$root/a.txt', 'x')
    ..removeRecursive('$root/a.txt');
  final epochs = await buildManifestSshFlushPlan(
    manifest: manifest, sourceFs: fs, workRoot: root, sameHost: false,
  );
  expect(epochs.map((e) => e.kind).toList(), [
    ManifestSshEpochKind.tar,
    ManifestSshEpochKind.script,
  ]);
  expect(epochs[1].script, contains('rm -rf'));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_ssh_flush_plan_test.dart`

Expected: FAIL.

- [ ] **Step 3: Write the planner**

Keep `manifest_ssh_flush_plan.dart` under ~400 lines. Copy tree listing can follow `ManifestExecutor._expandCopyTree` (`listDirRecursive`, skip directories, join names) but call `sourceFs.readBytes` instead of `utf8.decode`.

Export a small `posixShellQuote` used by extract command and mutation scripts so `manifest_executor.dart` can call the same quote helper later if needed — or duplicate the one-liner.

Make `_buildApplyScript` usable for mutation-only manifests: either move script generation into this file as `buildMutationApplyScript(LaunchManifest)` (mkdir/ln/rm/mv/cp only) or call `ManifestExecutor.debugBuildApplyScript` for same-host and mutation-only tiny manifests.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_ssh_flush_plan_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

---

### Task 6: Wire `ManifestExecutor.flush` to stdin epochs + logging

**Files:**
- Modify: `client/lib/services/launch/manifest_executor.dart`
- Modify: `client/test/services/launch/manifest_executor_ssh_test.dart`
- Test also: existing `manifest_filesystem_test.dart` `debugBuildApplyScript` cases stay

**Interfaces:**
- Consumes: `WorkPlaneScriptRunner.runScript` / `runStdinCommand` (Task 2), `buildManifestSshFlushPlan` (Task 5)
- Produces: SSH `flush` no longer `expandCopies` + `_flushViaSsh` of one huge script

- [ ] **Step 1: Write / update failing tests**

In `manifest_executor_ssh_test.dart`, extend `_RunnableClient.runWithResult` to record `command` and `stdin`.

- `same-host ssh flush runs remote cp without expanding copies`: exec command is `bash -s`; stdin contains `cp -R`; stdin does not contain `cat >`.
- `cross-machine ssh flush copies external symlink targets`: exec command is the gzip|tar pipeline (or `bash -s` only for a tiny mutation); **stdin is gzip**, not a heredoc containing `credentials`. Decode gzip/tar and expect file content `credentials` at the relative path under `symlinkProjectionRoot`.
- Keep `ssh manifest flush keeps storage pool alive`.
- Add: `off-home flush logs done after stdin apply` — optional if you assert `gzipTar` path via captured commands instead.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_executor_ssh_test.dart`

Expected: FAIL (still `cat >` / exec command is the full script).

- [ ] **Step 3: Implement flush**

Replace the SSH branch of `flush` with:

```dart
if (runner != null) {
  final sameHost = identical(sourceFs, targetFs);
  final workRoot = (symlinkProjectionRoot ?? '').trim();
  final epochs = await buildManifestSshFlushPlan(
    manifest: manifest,
    sourceFs: sourceFs,
    workRoot: workRoot.isEmpty ? '/' : workRoot,
    sameHost: sameHost,
  );
  var tarEpochs = 0;
  var scriptEpochs = 0;
  var stdinBytes = 0;
  for (final epoch in epochs) {
    switch (epoch.kind) {
      case ManifestSshEpochKind.script:
        scriptEpochs++;
        stdinBytes += utf8.encode(epoch.script!).length;
        await runner.runScript(
          epoch.script!,
          operation: 'Launch manifest apply',
        );
      case ManifestSshEpochKind.tar:
        tarEpochs++;
        stdinBytes += epoch.gzipTar!.length;
        await runner.runStdinCommand(
          command: epoch.extractCommand!,
          stdin: epoch.gzipTar!,
          operation: 'Launch overlay extract',
        );
    }
  }
  appLogger.d(
    '[session-launch] manifest flush via ssh '
    'ops=${manifest.entries.length} epochs=${epochs.length} '
    'scriptEpochs=$scriptEpochs tarEpochs=$tarEpochs stdinBytes=$stdinBytes',
  );
  return;
}
```

Delete `_flushViaSsh` or keep it unused — remove it. Keep `_buildApplyScript` / `debugBuildApplyScript` if the planner still uses them; otherwise move script builder next to the planner and re-export `debugBuildApplyScript` as a one-liner wrapper so `manifest_filesystem_test` compiles.

Do **not** call `_expandCopies` on the SSH path.

- [ ] **Step 4: Run related tests**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/manifest_executor_ssh_test.dart test/services/launch/manifest_filesystem_test.dart test/services/launch/work_plane_script_runner_test.dart`

Expected: PASS.

- [ ] **Step 5: `flutter analyze` on touched launch files**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/services/launch lib/services/ssh`

Expected: no issues in these dirs.

- [ ] **Step 6: Commit** (only if the user asked)

---

### Task 7: Personal SSH reconnect surfaces session failure

**Files:**
- Modify: `client/lib/services/launch/session_ssh_profile_reconnect.dart`
- Test: `client/test/services/launch/session_ssh_profile_reconnect_test.dart`

**Interfaces:**
- Consumes: `SessionShellConnector.connect` → `ConnectShellResult`
- Produces: `_reconnectPersonalTab` throws if result is `failed` or `aborted` (after existing `failSessionConnect` logging inside `connect`)

- [ ] **Step 1: Write the failing test**

Construct `SessionSshProfileReconnect` with a fake `SessionShellConnector` is heavy (large constructor). Prefer a thin seam:

Add `@visibleForTesting` static (or top-level) in `session_ssh_profile_reconnect.dart`:

```dart
void throwIfReconnectConnectFailed(ConnectShellResult result) {
  if (result == ConnectShellResult.failed ||
      result == ConnectShellResult.aborted) {
    throw StateError('session reconnect ${result.name}');
  }
}
```

Call it in `_reconnectPersonalTab` on the `connect` return value.

Test:

```dart
test('failed connect result is a reconnect error', () {
  expect(
    () => throwIfReconnectConnectFailed(ConnectShellResult.failed),
    throwsA(isA<StateError>()),
  );
});

test('attached connect result is success', () {
  throwIfReconnectConnectFailed(ConnectShellResult.attached);
});
```

In `_reconnectPersonalTab`:

```dart
final result = await _shellConnector.connect(/* existing args */);
throwIfReconnectConnectFailed(result);
_host.updateTabRunning(tab.info.id);
```

The existing `on Object catch` already calls `failSessionConnect`. Coordinator `_runReconnect` then hits `reconnectFailed` and schedules the next attempt instead of logging `reconnect succeeded`.

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_ssh_profile_reconnect_test.dart`

Expected: FAIL (helper missing / connect result ignored).

- [ ] **Step 3: Implement the throw + call site**

As in Step 1. Do not change team-member `scheduleMemberConnect` in this task.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/launch/session_ssh_profile_reconnect_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit** (only if the user asked)

---

## Spec coverage

| Spec item | Task |
|-----------|------|
| stdin CHANNEL_DATA for large payloads | 1, 2 |
| `bash -s` for scripts | 2, 6 |
| tar extract pipeline, not `bash -s` | 4, 5, 6 |
| off-home overlay tar, raw bytes | 5, 6 |
| epochs / rm-then-write order | 5 |
| path sandbox, not whole root | 4 |
| same-host `cp` script on stdin | 2, 5, 6 |
| `inFlight > 1` skip probe | 3 |
| reconnect failed ≠ profile success | 7 |
| flush logging with sizes | 6 |
| Out of scope (full-root tar, SFTP apply, dartssh2 max-packet) | none |

## Placeholder scan

No TBD/TODO left. `findFile` / `ArchiveFile` content accessors in tests must match archive 4.2 at implementation time — if the first overlay test fails on API names, fix the test to the real getters (`getContent()?.toUint8List()`, `symbolicLink`).
