# Unified home pane title design

**Date:** 2026-08-01  
**Status:** Approved for planning  
**Problem:** Home workspace body panes use inconsistent page titles. 「全部工作区」is the intended standard (`styles.xl` + 16 + Divider + 16, no subtitle, no header-owned padding). Other panes still use `WorkspaceHubTitleBar` (title + subtitle + self padding) or ad-hoc headers (`WorkspaceSectionHeading`, library title without divider).

**Builds on:** `HomeAllWorkspacesPane`, `AutomationManagementPage`, `WorkspaceHubTitleBar`, `WorkspaceSectionHeading`, `HomePage` right-pane padding, hub management pages embedded via `HomeGlobalSection`.

## Goal

One pane header component for home body pages and the shared hub/desktop shells that embed the same pages, matching 「全部工作区」chrome. Subtitles exist in the API but are **hidden by default**.

## Decisions (locked)

| Topic | Choice |
|-------|--------|
| Scope | Home sidebar body panes + shared hub shells that own the same title bar (`WorkspaceHubDesktopShell`, `WorkspaceHubPage`, My Teams / My Experts / Team Hub / Expert Hub / Skills / Plugins / MCP / Extensions / Providers / Automations / Favorites / Recent / All Workspaces). Config `/config/*` pages that already use `WorkspaceSectionHeading` also migrate to the same component for one title system. |
| Out of scope | Team identity config chrome (`HomeTeamHeader` + tab bar) — keep as-is |
| Architecture | New `WorkspacePaneHeader`; delete `WorkspaceHubTitleBar` and `WorkspaceSectionHeading` (no compat wrappers) |
| Visual standard | Title `TpTextStyles.xl` → 16 → Divider → 16; header widget has **zero** outer padding |
| Subtitle | `subtitle` optional; render only when `showSubtitle: true` **and** subtitle is non-empty. Default `showSubtitle: false` for all migrated call sites unless a page explicitly needs it |
| Padding ownership | Parent shells own inset. Extract shared `WorkspacePaneInsets` (or equivalent constant) from today’s home `EdgeInsets.fromLTRB(44, 48, 42, 18)` and apply to hub desktop shells / standalone hub pages so titles align when embedded or routed |
| Compact mode | Removed (no `compact` flag) |
| Back affordance | Optional `onBack` on `WorkspacePaneHeader` (replaces TitleBar back row) |
| Content alignment | My Teams / My Experts (and similar) drop extra horizontal padding that assumed TitleBar self-padding; body content aligns to the same pane inset as the title |
| Backward compatibility | None — break call sites in one change |

## Non-goals

- Restyling team identity tabs / `HomeTeamHeader` badge row
- Changing sidebar labels or navigation structure
- Adding a user-facing “show subtitle” preference
- Pixel-perfect matching of every config page’s historical spacing beyond the shared inset + header rhythm
- New design-system tokens beyond reusing existing `TpTextStyles` / divider color

## Invariants

1. **Single header widget** for pane titles in scope — no parallel TitleBar / SectionHeading implementations.
2. **Header never sets horizontal/vertical page inset** — only title block + divider rhythm.
3. **Subtitle off by default** — call sites may pass `subtitle` for future use, but must set `showSubtitle: true` to display it.
4. **Home and standalone hub routes share the same inset constant** so embedding in `HomePage` does not double-pad.
5. **Divider color** matches all-workspaces: `cs.outlineVariant.withValues(alpha: 0.5)`.

## Design

### 1. `WorkspacePaneHeader`

Location: `client/lib/widgets/settings/workspace_pane_header.dart` (or adjacent under `widgets/settings/`; keep next to hub shell).

```dart
class WorkspacePaneHeader extends StatelessWidget {
  const WorkspacePaneHeader({
    required this.title,
    this.subtitle,
    this.showSubtitle = false,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool showSubtitle;
  final VoidCallback? onBack;
}
```

Layout:

```text
[optional back IconButton + gap]
Column(
  title Text(styles.xl),
  if (showSubtitle && subtitle trim non-empty) ...[
    SizedBox(8),
    Text(subtitle, styles.md @ 0.66 alpha),
  ],
  SizedBox(16),
  Divider(height: 1, outlineVariant @ 0.5),
  SizedBox(16),
)
```

No container padding. No bottom `BoxDecoration` border (the Divider is the only separator).

### 2. Shared pane insets

Introduce a small constants holder (name bikeshed OK; intent is one source of truth), e.g.:

```dart
abstract final class WorkspacePaneInsets {
  static const EdgeInsets page = EdgeInsets.fromLTRB(44, 48, 42, 18);
}
```

Use in:

- `HomePage` right pane (replace local literal)
- `WorkspaceHubDesktopShell` / `WorkspaceHubPage` outer column (so removing TitleBar padding does not collapse standalone routes)
- Any other migrated shell that previously relied on TitleBar’s `fromLTRB(40, 42, 40, 28)` / compact padding

Android hub navigation that already uses `WorkspaceSectionPage` padding stays on its platform path; if it currently embeds TitleBar, switch to `WorkspacePaneHeader` and keep section-page padding as the outer inset (do not double-apply `WorkspacePaneInsets.page` on Android if the section page already insets).

### 3. Call-site migration

| Surface | Change |
|---------|--------|
| `HomeAllWorkspacesPane` | Replace inline title+divider with `WorkspacePaneHeader` |
| `HomeLibrarySection` | Same; add missing divider rhythm |
| `AutomationManagementPage` | Same |
| `WorkspaceHubDesktopShell` / `WorkspaceAdaptiveSectionPage` | TitleBar → `WorkspacePaneHeader`; honor `embedded` so home does not double-pad |
| Skills / Plugins / MCP / Extensions (via adaptive shell) | Inherit shell change; default `showSubtitle: false` |
| `MyTeamsPage` / `MyExpertsPage` | Header swap; normalize content padding to pane inset |
| `TeamHubPage` / `ExpertHubPage` | Header swap (list mode only) |
| `LlmConfigWorkspace` | `WorkspaceSectionHeading` → `WorkspacePaneHeader`; remove wrapper `Padding(16,12,16,8)` that would stack on header rhythm |
| Config `/config/*` sections using `WorkspaceSectionHeading` | Same swap (one title system; include in plan sweep) |
| `workspace_settings_view` / `error_page` | Same swap |
| `WorkspaceHubPage` | Header swap; apply pane inset when not embedded |

When replacing `WorkspaceSectionHeading`, drop any adjacent spacer that duplicated the old “subtitle gap + body gap”; the header already owns the 16 / Divider / 16 rhythm.

Delete unused: `WorkspaceHubTitleBar`, `WorkspaceSectionHeading`, and any `compact` padding branches only used by the old title bar.

Default for every migrated call site: `showSubtitle: false`. Do **not** turn subtitles on during this change unless a product callout is explicitly required (none for v1).

### 4. Shell composition

```text
Parent padding (WorkspacePaneInsets.page or platform section padding)
  └─ Column
       ├─ WorkspacePaneHeader(title: …)
       └─ Expanded(body)
```

`WorkspaceHubDesktopShell` becomes: pane inset (if not already provided by parent) + header + split nav/body. When the same page is embedded under `HomePage`, the home right pane already applies `WorkspacePaneInsets.page` — the shell must **not** pad again. Prefer: home embeds the body widget with header already inside the page; shells used from routes own the inset. Avoid nesting two `WorkspacePaneInsets.page`.

Concrete rule:

- **Route entry** (`/skills`, `/home-v2?global=…` content that is the page itself): page or shell applies inset once.
- **Home embed**: `HomePage` applies inset once; child pages must not re-apply the same page inset.

Today home already pads; hub pages also self-pad via TitleBar. After the change, hub pages embedded in home should assume **home owns inset** (header has zero padding). Standalone hub routes need the shell/page to apply `WorkspacePaneInsets.page`. Implementation may pass `EdgeInsets? inset` into the adaptive shell, or split “chrome page” vs “embedded body” — prefer the smallest clear API (e.g. `embedded: bool` on the adaptive section page that skips outer inset when true). Home global section already embeds full pages, so **`embedded: true` (or equivalent) on home-hosted management pages** is the intended path.

### 5. Testing

- Widget test for `WorkspacePaneHeader`: title only by default; subtitle appears only with `showSubtitle: true` + non-empty text; divider present; `onBack` shows leading control.
- Smoke/update existing page tests that assert on old TitleBar padding or subtitle visibility.
- No golden required for v1.

## Error handling

N/A (pure layout). Empty `title` is a caller bug; do not special-case.

## Extensibility

Later additions (actions row, trailing widgets, density) belong on `WorkspacePaneHeader` — not a second header type. Prefer optional slots (`actions`, `trailing`) only when a real call site needs them; v1 does not add unused slots (YAGNI).
