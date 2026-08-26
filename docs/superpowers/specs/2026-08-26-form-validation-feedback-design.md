# Form Validation Feedback — Design

Date: 2026-08-26
Status: Approved (design dialogue 2026-08-26)

## Problem

Many forms in the app fail silently: the user clicks Save with a missing
required field and nothing happens — no error message, no focus change. The
reported example is the model preset dialog (`cli_preset_edit_dialog.dart`),
which returns early when the name is empty.

Root cause: `shared_ui` already ships complete validation infrastructure
(`TpForm`, `TpFormField`, `TpInputFormField`, `TpTextareaFormField`) and several
forms use it correctly (SSH profile, automations, MCP editor, expert editor).
Adoption is inconsistent, and `TpSelect` has no error-state support at all, so
select-based forms cannot show inline errors.

## Decisions (from brainstorming)

- **Scope:** sweep all broken forms in one pass.
- **Interaction:** save buttons are always enabled; validation runs on click.
  Invalid fields get an inline red border + error text below the control, and
  focus moves to the first invalid field (`TpForm.validate()` already does
  this). No disabled-without-explanation buttons.
- **Approach:** migrate all affected forms onto the existing `TpForm` pattern;
  fill the single infrastructure gap (`TpSelect` error state).

Rejected alternatives: toast-only summaries (error far from field, style
split), infra-only fix without migrating forms (leaves the debt).

## Part 1 — shared_ui infrastructure

### TpSelect error state

- Add `bool hasError = false` to `TpSelect`.
- When true, the closed trigger border uses `ColorScheme.error`; the expanded
  (menu-open) state keeps the primary highlight, matching Material convention.
- Implementation lives in `TpSelectDecorations.themed(..., hasError:)`
  (switch border color); `TpSelect.build()` passes it through.

### New `TpSelectFormField<T extends Object>`

- File: `client/packages/shared_ui/lib/src/components/select/tp_select_form_field.dart`.
- Mirrors `TpInputFormField`: extends `TpFormField<T>`, builder renders
  `TpSelect(hasError: state.hasError, initialItem: value, onChanged: (v) =>
  state.didChange(v), ...)`. Error text is rendered below the control by
  `TpFormFieldLayout`.
- Supports `validator`, `label`, `error`, `description`, `enabled`,
  `autovalidateMode`, plus select passthroughs (`items`, `itemLabel`,
  `itemBuilder`, `hintText`).
- Export from `shared_ui.dart`.

Result: select fields get the same "red border + inline error" experience as
inputs, participate in `TpForm.validate()` focus-first-invalid flow, and can be
targeted by `setFieldError(id, msg)` for post-model errors.

## Part 2 — form conventions

1. Wrap form content in `TpForm(key: _formKey)`; fields use
   `TpInputFormField` / `TpSelectFormField` / `TpTextareaFormField` with
   `validator:` where required.
2. Save button always enabled: `onPressed: _save`; `_save` starts with
   `if (!(_formKey.currentState?.validate() ?? false)) return;`.
3. Remove silent returns and missing-data-disabled save buttons. A control may
   only be physically disabled (e.g., async loading). Missing data (empty
   provider list) surfaces as a validation error or empty-state guidance
   (`TpSelect.onEmptyTap`) instead of a grey button.
4. Async save failures keep the existing `AppToast` error pattern — no new
   mechanism.
5. l10n: add one generic key `formFieldRequired`
   (en: "This field is required." / zh: "此项为必填。"). Forms reuse it unless a
   semantic key already exists (SSH keeps its own).

## Part 3 — migration list

Already-compliant forms (ssh_profile_form_dialog, automation_editor,
mcp_editor, expert_editor) are untouched and serve as reference implementations.
All paths below are relative to `client/lib/`.

| # | Form | Current behavior | Change |
|---|------|------------------|--------|
| 1 | Model preset `pages/home_workspace/workspace/config/cli_preset_edit_dialog.dart` | Silent return on empty name; provider-missing disables Save | TpForm + name/provider validators; Save always enabled |
| 2 | LLM model edit `pages/llm_config/llm_model_edit_dialog.dart` | Silent return on empty name | Same |
| 3 | New workspace `pages/home_workspace/home_new_workspace_dialog.dart` | Silent return + disabled when no directory | Field-level errors |
| 4 | New team `pages/home_workspace/home_workspace_new_team_dialog.dart` | Silent return on empty name | Same |
| 5 | Onboarding default preset `pages/onboarding/steps/default_preset_step.dart` | Silent return on empty providerId | Select validation via `TpSelectFormField(validator:)` |
| 6 | Team member launch config `pages/team_config/team_member_launch_config_section.dart` | Silent return on empty preset token; provider-missing disables Save | Validate on click |
| 7 | Team default preset dialog `pages/team_config/team_default_preset_configure_dialog.dart` | Disabled Save + silent return | Same |
| 8 | Worktree create `pages/home_workspace/workspace/worktree_create_dialog.dart` | Branch-empty disables Save | Validate on click + required validator |
| 9 | Hook editor `pages/hooks/hook_editor_dialog.dart` | Silent return on empty id | Complete validation |
| 10 | Managed provider editor page `pages/managed_providers/managed_provider_editor_page.dart` | Page-level banner errors | Push errors down to fields |

## Part 4 — testing & acceptance

- **shared_ui tests:** `TpSelectFormField` widget test (initial value, selection
  callback, validator failure shows error text); `TpSelect.hasError` border
  assertion.
- **App test:** model preset dialog widget test — saving with an empty name
  keeps the dialog open and shows the required-field error; filling the name
  saves successfully. Other migrated forms run existing tests for regression.
- Acceptance: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
  && dart run tool/run_tests.dart`.

## Non-goals

Per-character realtime validation changes (keep current autovalidate policy),
cross-form validation framework rewrite, toast-summary approach.
