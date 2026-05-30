# Debugging Guide

Follow a systematic process when investigating bugs. Do NOT jump to fixes before understanding the root cause. **The most critical step is searching online — someone else has almost certainly hit the same bug and may have already found the real fix.**

## Process (in priority order)

### 1. Read the error carefully

Copy error messages, codes, stack traces verbatim. Note which ones are cascading consequences vs. root cause.

### 2. 🔍 Search online — DO THIS BEFORE PROPOSING FIXES

Copy the exact error message into search queries. Check GitHub issues, Flutter commits, other projects. This step is what separates finding the real root cause from wasting time on workarounds.

*Example from this repo:* `"Could not set client, view ID is null"` — searching led to [AppFlowy #1125](https://github.com/AppFlowy-IO/appflowy-editor/issues/1125) (same bug) and [Flutter commit 42988d1](https://github.com/flutter/flutter/pull/145708) (added `viewId` to `TextInputConfiguration`). The fix was a one-line parameter change, not timing hacks or error filtering.

**When searching is the right tool vs. local debugging:**

| Search | Local debug |
|--------|-------------|
| Error from framework/engine (`PlatformException`, `MethodChannel`, `JSONMethodCodec`) | Error in your own business logic |
| Error message is a fixed framework string (hard-coded in engine C++/Java) | Error message is custom app code |
| Cross-platform: works on Linux/Mac but fails on Windows | Same behavior on all platforms |
| API evolution: newer SDK version, things that used to work now break | Logic unchanged, just data-dependent |
| The stack trace has no paths under `client/lib/` | The stack trace points to files you own |

The bottom line: when the error **originates outside your code**, the root cause and fix are documented online — you just need to find them. Local debugging can only tell you *where* it fails, not *why* at the framework/engine level.

### 3. Trace the call chain

Walk backward from the error site through the code. For `PlatformException` from `MethodChannel._invokeMethod`, note that the async exception fires inside the framework — `try/catch` at the call site won't catch it because `invokeMethod` is fire-and-forget (no `await`).

### 4. Add diagnostic `debugPrint`

If the call chain doesn't make the cause obvious, add `debugPrint` at each step to verify hypotheses. Remove diagnostics after confirming.

### 5. Fix the root cause, not the symptom

Error filtering at `PlatformDispatcher` hides the problem. Timing hacks (`addPostFrameCallback`) guess at the cause. If the first fix doesn't work, re-examine your hypothesis — don't layer more workarounds.

### 6. Revert failed workarounds

Once the root cause is fixed, remove any intermediate defensive changes so future readers aren't confused.

## Common pitfalls

- **`TextInput.attach` on Windows:** requires `viewId` in `TextInputConfiguration` (Flutter 3.x multi-view). Get it from `PlatformDispatcher.instance.views.firstOrNull?.viewId`.
- **Async platform errors:** `MethodChannel.invokeMethod` returns `Future` — if not awaited, errors go to `PlatformDispatcher.instance.onError`. Can't be caught with `try/catch` at the call site.
- **Submodule changes:** `client/packages/flutter_alacritty` is a git submodule. Commit inside the submodule first, then update the pointer in the main repo.
