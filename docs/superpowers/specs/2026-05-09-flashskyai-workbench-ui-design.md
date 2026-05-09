# FlashskyAI Workbench UI Design

## Purpose

Design the next FlashskyAI Flutter client as a desktop workbench around the current shell wrapper flow. The app should feel like a chat-first operational tool, while still exposing team, member, layout, and LLM configuration clearly.

This design supersedes the earlier three-column-only sketch. The workspace now has a distinct app rail, context/sidebar area, and a main workspace whose top bar spans the center content and any right-side tools.

## Global Information Architecture

The app uses three persistent regions:

- App rail: global navigation such as Chat, Runs, Config, and Settings. It is narrow and icon-like.
- Context sidebar: scoped navigation for the active app area. In Chat, this contains team selector and team sessions. In Config, this contains configuration sections and relevant item lists.
- Workspace: the active working area. It owns a top tool/navigation/overview bar and the main page content.

Important layout rule:

- The workspace top bar spans the center content and right-side tools.
- The workspace top bar does not span the app rail or context sidebar.
- Pages that do not need right-side tools, especially configuration pages, use the full workspace width for their main content.

## Chat Workbench

Default chat layout:

- App rail on the far left.
- Context sidebar with current team selector at the top.
- Team sessions below the team selector.
- Workspace top bar spanning chat plus right tools.
- Center chat timeline and composer.
- Right-side tools stacked vertically: Members above File Tree.

The team selector belongs in the context sidebar, not in a global top tab. This keeps the UI from looking empty when only one team exists and avoids implying that team selection overrides the whole app chrome.

The center chat remains a shell-wrapper conversation:

- Sending adds a local user message.
- Sending copies the prompt to clipboard.
- A system message states that the prompt was copied and should be pasted into the FlashskyAI terminal.
- The UI must not imply that the prompt was sent to FlashskyAI unless a real bridge exists.

## Layout Configuration

Layout configuration is global, not per team or per session. Switching teams or sessions should preserve the user's spatial preferences.

Configuration controls structure only:

- Workbench structure preset, such as Workbench, Chat Focus, or Inspector.
- Tool panel placement, such as right side or bottom tray.
- Members and File Tree arrangement, such as stacked or tabs.
- Region visibility, such as app rail, team sessions, members, and file tree.

Panel sizes are not configured through settings forms. Widths and split ratios are adjusted by dragging dividers directly in the workbench and are remembered globally.

Default layout:

- Workbench preset.
- Right-side tool panel.
- Members and File Tree stacked vertically.
- Sizes are draggable and persisted globally.

## Team Configuration

Team configuration is a first-class Config workspace view, not a modal.

The Team Config page uses:

- App rail with Config selected.
- Context sidebar with team selector, config navigation, and member quick list.
- Workspace top bar with breadcrumb, current team summary, save actions, and relevant status.
- Full-width configuration content without the chat right-side tools.

Fields:

- Team name.
- Working directory.
- Team extra CLI arguments.
- Member launch order and quick member actions.

Working directory should use a directory picker plus recent paths. It should validate that the directory exists and show readable errors for missing or inaccessible paths.

## Member Configuration

Member configuration is also a Config workspace view, not a modal.

The Member Config page uses:

- Context sidebar for selecting members.
- Workspace top bar showing selected team, member, and status.
- Main form for member identity and launch fields.
- Command preview and validation inside the main content area.

Fields:

- Member name.
- Provider.
- Model.
- Agent.
- Member extra CLI arguments.

Provider, model, and agent should use searchable dropdowns or comboboxes. They should offer known values and allow custom values so the UI does not block newly released models or custom providers.

The `team-lead` member needs special treatment:

- The UI should show that FlashskyAI team delegation expects a member named exactly `team-lead`.
- Renaming or deleting `team-lead` should be guarded with clear validation.

## LLM Configuration

The LLM Config page edits `flashshkyai/llm/llm_config.json`.

It belongs under Config alongside Team, Members, and Layout.

Workspace structure:

- Context sidebar lists Config sections and provider shortcuts.
- Workspace top bar shows the file path, provider count, model count, validation summary, and save actions.
- Main content uses tabs: Providers, Models, Raw JSON.
- No chat-style right sidebar by default.

Provider editor:

- Provider name.
- Type: `api` or `account`.
- Provider type, such as OpenAI-compatible, Claude-compatible, or custom.
- Base URL for API providers.
- API key for API providers.
- Proxy toggle.
- Proxy URL when proxy is enabled.
- Account credential path list for account providers.

Models editor:

- Model alias/name.
- Provider dropdown.
- Actual model id.
- Enabled toggle.
- Edit/delete actions.

Validation:

- Warn when a model references a missing provider.
- Warn when an API provider is missing required fields.
- Warn when account credential paths are missing or inaccessible.
- Show empty API keys as configuration warnings.

Secret handling:

- API keys are masked by default.
- Revealing a key requires an explicit user action.
- Saving must not overwrite an unchanged secret with placeholder mask characters.
- JSON previews must mask secret values.

Raw JSON tab:

- Provides an escape hatch for advanced editing.
- Should preserve unknown fields where possible.
- Should validate JSON before saving.

## Guided Controls

Use guided controls for high-value configuration:

- Provider: searchable combobox with known providers and custom value.
- Model: searchable combobox filtered by provider, with custom value.
- Agent: role preset dropdown with custom value.
- Working directory: directory picker, recent paths, and validation.
- Proxy: toggle plus conditional proxy URL field.
- Enabled flags: toggles.

Keep advanced CLI arguments as text fields because the possible flags are open-ended.

## Modals and Drawers

Primary configuration should live in the Config workspace, not in modal dialogs.

Use modals or drawers only for small auxiliary tasks:

- Add team.
- Add member.
- Confirm delete.
- Choose directory.
- Reveal or replace API key.
- Quick rename.
- Copy/save success or error details.

## Persistence

Persist globally:

- Layout structure preset.
- Tool panel placement.
- Members/File Tree arrangement.
- Region visibility.
- Last dragged panel sizes and split ratios.

Persist in app configuration:

- Teams and members.
- Chat/session local history, if implemented in the selected phase.
- LLM config updates to `flashshkyai/llm/llm_config.json`.

## Implementation Notes

The first implementation can still be phased:

1. Build the corrected workspace shell with app rail, context sidebar, workspace topbar, chat center, and right-side tools.
2. Add global layout preferences and draggable persisted sizes.
3. Build Config workspace views for Team and Member configuration.
4. Build LLM Config editor for providers and models.
5. Add Raw JSON editing after structured editing is stable.

The UI should stay desktop-workbench oriented: dense, calm, readable, and operational. Avoid marketing-style hero sections, nested cards, and oversized decorative surfaces.
