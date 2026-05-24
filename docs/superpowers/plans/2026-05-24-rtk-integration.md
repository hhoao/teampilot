# RTK Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let TeamPilot optionally inject RTK PreToolUse hooks into per-member `flashskyai` / `claude` config dirs so Agent Bash commands are transparently rewritten to `rtk`, reducing LLM token usage.

**Architecture:** Ship `rtk-rewrite.sh` as a Flutter asset; `RtkHookProvisioner` copies it into each member tool dir and builds a settings fragment; `RtkSettingsMerge` prepends RTK without removing provider hooks; `ConfigProfileService` calls provision during settings write when `AppSettingsRepository.rtkEnabled` is true and `RtkDetector` succeeds.

**Tech Stack:** Dart / Flutter, `shared_preferences`, existing `Filesystem` / `ConfigProfileService` / `SessionLifecycleService`.

**Spec:** [`docs/superpowers/specs/2026-05-24-rtk-integration-design.md`](../specs/2026-05-24-rtk-integration-design.md)

---

## File map

| File | Responsibility |
|------|----------------|
| `client/assets/rtk/rtk-rewrite.sh` | Upstream hook script (pinned copy) |
| `client/lib/services/rtk_detector.dart` | Probe `rtk` / `jq` on PATH |
| `client/lib/services/rtk_settings_merge.dart` | Merge `hooks.PreToolUse` into settings map |
| `client/lib/services/rtk_hook_provisioner.dart` | Copy script + build fragment |
| `client/lib/services/config_profile_service.dart` | Call provision + merge on write |
| `client/lib/repositories/app_settings_repository.dart` | `rtkEnabled` persistence |
| `client/lib/pages/config_workspace.dart` | Settings UI section |
| `client/lib/l10n/app_*.arb` | Strings |
| `client/test/services/rtk_*_test.dart` | Unit tests |

---

## Phase 1 — Core services (no UI)

### Task 1: Vendor hook script asset

**Files:**
- Create: `client/assets/rtk/rtk-rewrite.sh` (copy from RTK `hooks/claude/rtk-rewrite.sh` @ tag v0.41.0 or `develop`)
- Modify: `client/pubspec.yaml` (add asset entry)

- [ ] **Step 1: Copy script**

Copy upstream `rtk-rewrite.sh` verbatim into `client/assets/rtk/rtk-rewrite.sh`.

- [ ] **Step 2: Register asset in pubspec**

```yaml
flutter:
  assets:
    - assets/rtk/rtk-rewrite.sh
```

- [ ] **Step 3: Verify asset loads**

```bash
cd client && flutter pub get
```

---

### Task 2: `RtkSettingsMerge`

**Files:**
- Create: `client/lib/services/rtk_settings_merge.dart`
- Test: `client/test/services/rtk_settings_merge_test.dart`

- [ ] **Step 1: Write failing tests**

```dart
// client/test/services/rtk_settings_merge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/rtk_settings_merge.dart';

void main() {
  group('RtkSettingsMerge', () {
    test('adds hooks.PreToolUse when absent', () {
      const merge = RtkSettingsMerge();
      final out = merge.mergeIntoSettings(
        base: {'skipDangerousModePermissionPrompt': true},
        hookCommand: 'bash "/tmp/hooks/rtk-rewrite.sh"',
      );
      final hooks = out['hooks'] as Map;
      final pre = hooks['PreToolUse'] as List;
      expect(pre, hasLength(1));
      expect(pre.first['matcher'], 'Bash');
    });

    test('is idempotent when RTK hook already present', () {
      const merge = RtkSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Bash',
              'hooks': [
                {
                  'type': 'command',
                  'command': 'bash "/tmp/hooks/rtk-rewrite.sh"',
                },
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: 'bash "/tmp/hooks/rtk-rewrite.sh"',
      );
      expect(out, base);
    });

    test('prepends RTK before existing PreToolUse matchers', () {
      const merge = RtkSettingsMerge();
      final base = {
        'hooks': {
          'PreToolUse': [
            {
              'matcher': 'Bash',
              'hooks': [
                {'type': 'command', 'command': 'echo other'},
              ],
            },
          ],
        },
      };
      final out = merge.mergeIntoSettings(
        base: base,
        hookCommand: 'bash "/tmp/rtk.sh"',
      );
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre, hasLength(2));
      expect(
        (pre.first as Map)['hooks'],
        contains(isA<Map>().having(
          (m) => (m as Map)['command'],
          'command',
          contains('rtk'),
        )),
      );
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd client && flutter test test/services/rtk_settings_merge_test.dart
```

- [ ] **Step 3: Implement**

```dart
// client/lib/services/rtk_settings_merge.dart
class RtkSettingsMerge {
  const RtkSettingsMerge();

  static const _rtkMarker = 'rtk-rewrite';

  Map<String, Object?> mergeIntoSettings({
    required Map<String, Object?> base,
    required String hookCommand,
  }) {
    if (_hasRtkHook(base)) return base;
    final fragment = _rtkPreToolUseEntry(hookCommand);
    final hooks = Map<String, Object?>.from(
      (base['hooks'] as Map?)?.cast<String, Object?>() ?? const {},
    );
    final existing = List<Object?>.from(
      (hooks['PreToolUse'] as List?) ?? const [],
    );
    hooks['PreToolUse'] = [fragment, ...existing];
    return {...base, 'hooks': hooks};
  }

  bool _hasRtkHook(Map<String, Object?> base) {
    final pre = (base['hooks'] as Map?)?['PreToolUse'];
    if (pre is! List) return false;
    for (final entry in pre) {
      if (entry is! Map) continue;
      final inner = entry['hooks'];
      if (inner is! List) continue;
      for (final h in inner) {
        if (h is Map && (h['command']?.toString().contains(_rtkMarker) ?? false)) {
          return true;
        }
      }
    }
    return false;
  }

  Map<String, Object?> _rtkPreToolUseEntry(String hookCommand) => {
    'matcher': 'Bash',
    'hooks': [
      {'type': 'command', 'command': hookCommand},
    ],
  };
}
```

- [ ] **Step 4: Run test — expect PASS**

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/rtk_settings_merge.dart client/test/services/rtk_settings_merge_test.dart
git commit -m "feat(rtk): add settings hook merge helper"
```

---

### Task 3: `RtkDetector`

**Files:**
- Create: `client/lib/services/rtk_detector.dart`
- Test: `client/test/services/rtk_detector_test.dart`

- [ ] **Step 1: Write failing test** (mock-free: test `isVersionSupported` pure logic)

```dart
test('isVersionSupported requires >= 0.23.0', () {
  const d = RtkDetector();
  expect(d.isVersionSupported('0.41.0'), isTrue);
  expect(d.isVersionSupported('0.22.9'), isFalse);
  expect(d.isVersionSupported('1.0.0'), isTrue);
});
```

- [ ] **Step 2: Implement `RtkDetector`**

- `probe()`: `which rtk` / `where rtk`, then `rtk --version`, then `which jq`.
- Parse version with regex `rtk\s+(\d+\.\d+\.\d+)`.
- Return `RtkProbeResult`.

- [ ] **Step 3: Run tests PASS**

- [ ] **Step 4: Commit**

---

### Task 4: `RtkHookProvisioner`

**Files:**
- Create: `client/lib/services/rtk_hook_provisioner.dart`
- Test: `client/test/services/rtk_hook_provisioner_test.dart`

- [ ] **Step 1: Write failing test** using in-memory / temp dir `Filesystem`

Assert:
- `hooks/rtk-rewrite.sh` created under member dir
- `hookCommandForPath` returns `bash "<absolute>/hooks/rtk-rewrite.sh"`

- [ ] **Step 2: Implement**

Constructor takes `AssetBundle` or `String hookAssetPath` for tests.

```dart
Future<String> provisionMemberToolDir(String memberToolDir) async {
  final hooksDir = p.join(memberToolDir, 'hooks');
  await _fs.ensureDir(hooksDir);
  final dest = p.join(hooksDir, 'rtk-rewrite.sh');
  await _fs.writeString(dest, await _loadAssetScript());
  await _fs.chmodExecutable(dest); // no-op on Windows test fs
  return dest;
}

String hookCommandForPath(String scriptPath) =>
    'bash "${scriptPath.replaceAll('"', r'\"')}"';
```

Load asset via `rootBundle.loadString('assets/rtk/rtk-rewrite.sh')` in production; inject string in tests.

- [ ] **Step 3: Run tests PASS**

- [ ] **Step 4: Commit**

---

### Task 5: Wire `ConfigProfileService`

**Files:**
- Modify: `client/lib/services/config_profile_service.dart`
- Test: `client/test/services/config_profile_service_rtk_test.dart` (new)

- [ ] **Step 1: Extend constructor**

```dart
ConfigProfileService({
  ...
  RtkHookProvisioner? rtkProvisioner,
  RtkDetector? rtkDetector,
  Future<bool> Function()? loadRtkEnabled,
})
```

Defaults: real instances; tests pass `loadRtkEnabled: () async => true` and fake detector returning success.

- [ ] **Step 2: Add private method**

```dart
Future<Map<String, Object?>> _maybeApplyRtk(
  Map<String, Object?> settings,
  String memberToolDir,
) async {
  if (!await (loadRtkEnabled?.call() ?? () async => false)()) {
    return settings;
  }
  final probe = await (_rtkDetector ?? RtkDetector()).probe();
  if (!probe.found || !probe.jqFound) return settings;
  if (probe.version != null &&
      !(_rtkDetector ?? RtkDetector()).isVersionSupported(probe.version!)) {
    return settings;
  }
  final script = await (_rtkProvisioner ?? ...).provisionMemberToolDir(memberToolDir);
  final cmd = (_rtkProvisioner ?? ...).hookCommandForPath(script);
  return const RtkSettingsMerge().mergeIntoSettings(base: settings, hookCommand: cmd);
}
```

- [ ] **Step 3: Call from `_writeFlashskyaiSettings`, `_writeClaudeSettings`, `_writeClaudeMemberProfile`**

Pass `sessionToolDir(scope.teamId, scope.sessionId, tool)` as `memberToolDir`.

- [ ] **Step 4: Write test** — with fake FS, enabled RTK → written settings file contains `rtk-rewrite`.

- [ ] **Step 5: Run `flutter test test/services/config_profile_service_rtk_test.dart`**

- [ ] **Step 6: Commit**

---

### Task 6: Launch warnings

**Files:**
- Modify: `client/lib/services/session_lifecycle_service.dart` (or `config_profile_service` return warnings)
- Modify: `client/lib/services/config_profile_service.dart` — extend `TeamLaunchOutcome.warnings`

- [ ] **Step 1: When RTK enabled but probe fails, append warning codes**

`rtk_enabled_not_found`, `rtk_enabled_jq_missing`, `rtk_enabled_version_too_old`.

- [ ] **Step 2: Unit test warnings list**

- [ ] **Step 3: Commit**

---

## Phase 2 — Settings UI & persistence

### Task 7: `AppSettingsRepository.rtkEnabled`

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart`
- Modify: `client/test/...` if exists for app settings

- [ ] **Step 1: Add `loadRtkEnabled` / `saveRtkEnabled` (default `false`)**

Key: `rtkEnabled` in same JSON map as `llmConfigPath`.

- [ ] **Step 2: Update `InMemoryAppSettingsRepository`**

- [ ] **Step 3: Tests + commit**

---

### Task 8: Settings UI section

**Files:**
- Modify: `client/lib/pages/config_workspace.dart`
- Modify: `client/lib/l10n/app_en.arb`, `app_zh.arb`
- Run: `flutter gen-l10n`

- [ ] **Step 1: Add l10n keys**

`rtkSettingsTitle`, `rtkSettingsDescription`, `rtkStatusInstalled`, `rtkStatusNotFound`, `rtkStatusJqMissing`, `rtkBashOnlyHint`.

- [ ] **Step 2: `_RtkSettingsSection` StatefulWidget**

On init: `RtkDetector().probe()` for status label.
Switch: read/write `AppSettingsRepository.rtkEnabled`.
Link: `url_launcher` or `showDialog` with install URL.

- [ ] **Step 3: Insert in `_LayoutSettingsScroll` children**

- [ ] **Step 4: Manual smoke on Linux**

- [ ] **Step 5: Commit**

---

### Task 9: Inject dependencies in app shell

**Files:**
- Modify: `client/lib/app/app_shell.dart` or wherever `ConfigProfileService` is constructed

- [ ] **Step 1: Pass `loadRtkEnabled: () => appSettings.loadRtkEnabled()`**

- [ ] **Step 2: Provide `RtkHookProvisioner` with `rootBundle`**

- [ ] **Step 3: Commit**

---

## Phase 3 — Verification

### Task 10: Full test suite

- [ ] **Step 1: Run**

```bash
cd client && flutter test --exclude-tags integration
```

Expected: all pass.

- [ ] **Step 2: Fix failures**

---

### Task 11: Manual E2E checklist

- [ ] Install RTK: `curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh`
- [ ] Install `jq` if missing
- [ ] Enable RTK in TeamPilot settings
- [ ] Start flashskyai team session
- [ ] Inspect `<teampilotRoot>/config-profiles/teams/.../members/.../flashskyai/settings.json` for `PreToolUse` + `hooks/rtk-rewrite.sh`
- [ ] In Agent session, trigger `git status` via Bash; output should be compact vs without RTK
- [ ] Disable RTK; restart session; settings should not contain RTK hook

---

## Out of scope (track as follow-ups)

- [ ] Codex `AGENTS.md` RTK block (`rtk init --codex` equivalent)
- [ ] Windows native PowerShell hook
- [ ] Bundle `rtk` binary in installer
- [ ] `rtk gain` dashboard in TeamPilot
- [ ] Upstream PR: `rtk init --agent teampilot`

---

## Plan self-review (spec coverage)

| Spec § | Task |
|--------|------|
| Hook merge / 幂等 | Task 2, 5 |
| Member hooks dir | Task 4, 5 |
| flashskyai + claude | Task 5 |
| Detector + warnings | Task 3, 6 |
| App settings + UI | Task 7, 8 |
| No bundle binary v1 | (implicit) |
| Platform Windows note | Task 8 copy + manual checklist |

---

**Plan complete.** Execution options:

1. **Subagent-Driven** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute in this session with executing-plans checkpoints

Which approach do you prefer?
