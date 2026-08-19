# TeamBus Prompt XML Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace TeamBus-generated human-readable control prompts with one XML-like `<teambus>` envelope and keep ordinary message payloads unchanged.

**Architecture:** Add one small formatter under `services/team_bus` that escapes text and attributes and emits `<teambus type="..." ...>...</teambus>`. Use it for Dart-generated doorbells, Stop-hook reasons, and idle-notification display text; update the OpenCode generated plugin literal separately because that asset is JavaScript source. Add only the minimal format example to mixed-team prompts.

**Tech Stack:** Dart, Flutter package:test, generated JavaScript plugin source, existing TeamBus/MCP services.

## Global Constraints

- Use one root element: `<teambus>`.
- Do not introduce `hook_prompt` or `hook_run_id`.
- Wrap only TeamBus-generated control blocks; do not wrap ordinary teammate/user message bodies or MCP envelopes.
- Preserve existing TeamBus routing, message IDs, task IDs, and hook decision JSON.
- Preserve diagnostic log prefixes such as `[team-bus]`.
- Use `apply_patch` for source edits and keep unrelated dirty-worktree changes untouched.

---

### Task 1: Add the shared TeamBus XML formatter

**Files:**
- Create: `client/lib/services/team_bus/teambus_prompt.dart`
- Create: `client/test/services/team_bus/teambus_prompt_test.dart`

**Interfaces:**
- Produces `TeamBusPrompt.format({required String type, required String content, Map<String, String> attributes = const {}})` returning one `<teambus>` element.

- [ ] **Step 1: Write failing formatter tests**

```dart
test('formats a teambus element with type first', () {
  expect(
    TeamBusPrompt.format(type: 'mail', content: 'Read the inbox.'),
    '<teambus type="mail">Read the inbox.</teambus>',
  );
});

test('preserves attribute order and escapes XML values', () {
  expect(
    TeamBusPrompt.format(
      type: 'message',
      attributes: {'message_id': 'm&1', 'from': 'a"b'},
      content: 'A & <B>',
    ),
    '<teambus type="message" message_id="m&amp;1" from="a&quot;b">'
    'A &amp; &lt;B&gt;</teambus>',
  );
});
```

- [ ] **Step 2: Run the formatter tests and verify they fail**

Run from `client/`:

```bash
flutter test test/services/team_bus/teambus_prompt_test.dart
```

Expected: FAIL because `TeamBusPrompt` does not exist yet.

- [ ] **Step 3: Implement the formatter**

```dart
abstract final class TeamBusPrompt {
  TeamBusPrompt._();

  static String format({
    required String type,
    required String content,
    Map<String, String> attributes = const {},
  }) {
    final values = <String, String>{'type': type, ...attributes};
    final attrs = values.entries
        .map((entry) => ' ${entry.key}="${_escape(entry.value)}"')
        .join();
    return '<teambus$attrs>${_escape(content)}</teambus>';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
```

- [ ] **Step 4: Run the formatter tests and verify they pass**

Run the same command. Expected: PASS.

- [ ] **Step 5: Commit the formatter**

```bash
git add client/lib/services/team_bus/teambus_prompt.dart client/test/services/team_bus/teambus_prompt_test.dart
git commit -m "feat: add TeamBus prompt XML formatter"
```

### Task 2: Wrap TeamBus runtime control prompts

**Files:**
- Modify: `client/lib/services/team_bus/team_bus.dart` (`doorbellNotice`, `taskDoorbellNotice`)
- Modify: `client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart` (`stopRedirectReason`)
- Modify: `client/lib/services/team_bus/idle_notification.dart` (`formatForLeader`)
- Modify: `client/lib/services/cli/opencode/capabilities/idle_plugin.dart` (generated redirect literal)
- Modify: `client/test/services/team_bus/idle_notification_test.dart`
- Modify: `client/test/services/cli/config_profile/opencode_idle_plugin_test.dart`

**Interfaces:**
- `TeamBus.doorbellNotice` and `TeamBus.taskDoorbellNotice` remain the existing public strings used by tests and delivery logic, but now contain `<teambus type="mail">…</teambus>` and `<teambus type="task">…</teambus>` respectively.
- `TeammateBusMcpHandler.stopRedirectReason` remains the existing public string, now wrapped as `type="stop_reason"`.
- `IdleNotification.formatForLeader()` remains the existing display method, now returning a `type="idle_notification"` wrapper around its current body.

- [ ] **Step 1: Add runtime assertions before changing producers**

Extend the existing focused tests with assertions such as:

```dart
expect(TeamBus.doorbellNotice, startsWith('<teambus type="mail">'));
expect(TeamBus.taskDoorbellNotice, startsWith('<teambus type="task">'));
expect(TeammateBusMcpHandler.stopRedirectReason,
    startsWith('<teambus type="stop_reason">'));
```

Add an idle-notification assertion that `formatForLeader()` starts with
`<teambus type="idle_notification"` while retaining the existing notification body.

- [ ] **Step 2: Run the focused tests and verify the new assertions fail**

```bash
flutter test \
  test/services/team_bus/idle_notification_test.dart \
  test/services/team_bus/team_bus_idle_doorbell_test.dart \
  test/services/cli/config_profile/opencode_idle_plugin_test.dart \
  test/services/cli/config_profile/flashskyai_stop_idle_hook_test.dart
```

Expected: FAIL on the new XML assertions.

- [ ] **Step 3: Wrap Dart-generated control text**

Keep raw body constants for internal equality checks, and expose the existing
public strings as formatted values:

```dart
static const _doorbellNoticeBody =
    'You have unread teammate messages — call '
    'read_messages(mark_read: true) to read them now, then handle them. '
    '(From the bus, not your operator.)';

static String get doorbellNotice => TeamBusPrompt.format(
  type: 'mail',
  content: _doorbellNoticeBody,
);
```

Apply the same pattern to the task notice and Stop-hook reason. Wrap the
existing idle-notification body after it has been assembled, passing only
attributes backed by existing fields.

- [ ] **Step 4: Update the OpenCode generated plugin literal**

Replace only the redirect string in `opencodeIdlePluginSource` with the same
wire format:

```js
const redirect =
  "<teambus type=\"stop_reason\">Do not stop. Call wait_for_message — it blocks until you " +
  "have something to do and returns either teammate/operator messages or a " +
  "task claimed for you from the work queue. You coordinate through the " +
  "bus, not by ending your turn.</teambus>";
```

- [ ] **Step 5: Run the focused tests and verify they pass**

Run the Task 2 test command again. Expected: PASS, with existing delivery,
hook-decision, and idle-notification assertions still passing.

- [ ] **Step 6: Commit the runtime wrapping**

```bash
git add client/lib/services/team_bus/team_bus.dart \
  client/lib/services/team_bus/mcp/teammate_bus_mcp_handler.dart \
  client/lib/services/team_bus/idle_notification.dart \
  client/lib/services/cli/opencode/capabilities/idle_plugin.dart \
  client/test/services/team_bus/idle_notification_test.dart \
  client/test/services/cli/config_profile/opencode_idle_plugin_test.dart
git commit -m "feat: wrap TeamBus control prompts in XML"
```

### Task 3: Synchronize mixed-team prompts with the implemented format

**Files:**
- Modify: `client/lib/services/session/member_role_provision.dart` (mixed lead, worker, and push-delivery addenda)
- Modify: `client/lib/services/ai/team_config_prompt_mixed.dart`
- Modify: `client/test/services/session/member_role_provision_prompt_test.dart`
- Modify: `client/test/services/ai/team_config_prompt_test.dart`

**Interfaces:**
- Mixed-team prompt generation includes only the literal format already emitted by runtime code: `<teambus type="...">...</teambus>`.

- [ ] **Step 1: Add failing prompt assertions**

```dart
test('mixed role prompt documents the TeamBus XML envelope', () {
  const member = TeamMemberConfig(id: 'm1', name: 'Member');
  final prompt = MemberRoleProvision.composeRolePrompt(
    member: member,
    mixed: true,
  );
  expect(prompt, contains('<teambus type="...">...</teambus>'));
});
```

Add the same exact-format assertion to the mixed team configuration prompt
test.

- [ ] **Step 2: Run the prompt tests and verify they fail**

```bash
flutter test \
  test/services/session/member_role_provision_prompt_test.dart \
  test/services/ai/team_config_prompt_test.dart
```

Expected: FAIL because the format example is not in the mixed prompts.

- [ ] **Step 3: Add the minimal format example**

Insert the single literal format example into the mixed role addenda and the
mixed team generation prompt. Do not add a type catalog, legacy-format note,
negative instructions, or unimplemented attributes.

- [ ] **Step 4: Run the prompt tests and verify they pass**

Run the same command. Expected: PASS.

- [ ] **Step 5: Commit the prompt synchronization**

```bash
git add client/lib/services/session/member_role_provision.dart \
  client/lib/services/ai/team_config_prompt_mixed.dart \
  client/test/services/session/member_role_provision_prompt_test.dart \
  client/test/services/ai/team_config_prompt_test.dart
git commit -m "docs: describe TeamBus prompt XML envelope"
```

### Task 4: Verify the complete change

**Files:**
- No new source files.

- [ ] **Step 1: Run all focused TeamBus and prompt tests**

```bash
cd client
flutter test \
  test/services/team_bus \
  test/services/session/member_role_provision_prompt_test.dart \
  test/services/ai/team_config_prompt_test.dart \
  test/services/cli/config_profile/opencode_idle_plugin_test.dart \
  test/services/cli/config_profile/flashskyai_stop_idle_hook_test.dart
```

Expected: exit code 0 with no failed tests.

- [ ] **Step 2: Run repository static analysis**

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: exit code 0.

- [ ] **Step 3: Run the non-integration test suite**

```bash
flutter test --exclude-tags integration
```

Expected: exit code 0 with no failed tests.

- [ ] **Step 4: Review the final diff**

```bash
git status --short
git diff --check
```

Confirm only the formatter, listed TeamBus/prompt files, focused tests, and
the two committed design/plan documents changed; unrelated pre-existing worktree
changes must remain untouched.
