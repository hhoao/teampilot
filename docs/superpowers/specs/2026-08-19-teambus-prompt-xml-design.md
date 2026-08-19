# TeamBus prompt XML format

## Goal

Use one XML element for TeamBus-generated prompt text so the prompt format is
consistent and can carry additional metadata later. The element name is
`teambus`; the implementation must not introduce a separate `hook_prompt`
element or a synthetic `hook_run_id` field.

The structure follows the production pattern visible in Anthropic's Claude
prompts: an XML-like element marks a system-generated control block, while
ordinary user/tool payloads remain ordinary payloads. See the referenced
Anthropic prompt collection:
<https://github.com/asgeirtj/system_prompts_leaks/tree/main/Anthropic>.

## Format

The common shape is:

```xml
<teambus type="..." ...>content</teambus>
```

`type` identifies the prompt kind. Additional attributes are optional and are
only emitted when the corresponding data already exists. Attribute names use
the existing TeamBus snake_case convention, for example `member_id`,
`message_id`, and `task_id`. XML content and attribute values must be escaped.

The first implementation covers the TeamBus-generated prompt surfaces that
currently use human-readable control text:

- mail doorbells injected into an idle member's terminal;
- task doorbells injected into an idle member's terminal;
- the Stop-hook redirect reason;
- the OpenCode idle plugin's equivalent redirect prompt;
- idle notifications rendered into mailbox tool content.

The MCP response envelope remains JSON. When a rendered mailbox entry is
wrapped, only its `content` string changes. Existing TeamBus message routing,
message IDs, task IDs, and hook decision JSON remain unchanged.

Ordinary teammate/user message bodies are not wrapped or assigned new
metadata. Diagnostics such as `[team-bus]` log prefixes are not part of the
prompt format and remain unchanged.

## Team prompts

The mixed-team role prompt and mixed-team configuration-generation prompt are
updated only with the actual common shape and fields emitted by the runtime:

```text
<teambus type="..." ...>content</teambus>
```

They do not add speculative type lists, legacy-format warnings, or additional
behavioral instructions. The role prompt itself remains a normal system prompt
file; it is not wrapped in `teambus`.

## Implementation boundaries

- Add one shared TeamBus formatter for the XML wrapper and escaping.
- Route all listed prompt producers through that formatter.
- Preserve the raw inner control text used for internal comparisons such as
  mail-versus-task doorbell detection.
- Update exact-string tests to assert the XML output and add formatter tests
  for attributes and escaping.
- Update prompt-generation tests only for the minimal common-format text.

## Verification

Run the focused TeamBus, idle-notification, Stop-hook, and prompt-provision
tests, followed by the repository-required Flutter analyze and non-integration
test commands.
