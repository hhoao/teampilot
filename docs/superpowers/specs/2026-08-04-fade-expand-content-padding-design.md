# Fade expand contentPadding (edge-flush mask)

## Problem

Collapsed chat surfaces that use `AiFadeExpandBody` put the fade/chevron strip **inside** an outer `Padding` on the colored bubble/card. The gradient therefore sits inset from the rounded bottom and side edges, leaving a visible gap between the mask and the surface border.

Affected today:

- User message bubble (`ai_message_view.dart`) — `Padding(horizontal: 16, vertical: 10)` wraps the fade host
- Shell tool card (`shell_tool_card.dart`) — `Padding(all: 10)` wraps the fade body
- Edit tool card — already edge-flush (`ClipRRect` + `ColoredBox` around `AiFadeExpandBody`); keep as the reference pattern

## Decision

**Invert padding ownership:** `AiFadeExpandBody` owns `contentPadding`. Content is padded; the fade/chevron overlay is `Positioned(left/right/bottom: 0)` flush to the host edges. Colored surfaces (`DecoratedBox` / `ClipRRect`) wrap `AiFadeExpandBody` directly — no outer padding around the fade host.

```
DecoratedBox / ClipRRect (surface color + radius)
└─ AiFadeExpandBody(contentPadding: …)
   ├─ Padding(contentPadding) → child
   └─ Positioned(left:0, right:0, bottom:0) → fade + chevron
```

Rejected alternatives:

- **overlayBleed / negative insets** — parents keep outer padding; bleed must stay manually synced; hit-testing and clip are fragile
- **Per-parent Stack overlays** — duplicates fade logic; conflicts with “fix every `AiFadeExpandBody` surface”

## API

`AiFadeExpandBody` gains:

```dart
final EdgeInsetsGeometry contentPadding; // default EdgeInsets.zero
```

Behavior unchanged unless padding is moved in:

- Collapsed clip / expanded scroll caps (`collapsedMaxHeight` / `expandedMaxHeight`)
- Height reporting and overflow chrome gating
- `_BlockBottomHits` for the hit strip
- Selection dead zone + mask pointer recognizer
- Hover brighten on the fade strip

Collapsed host height continues to include `contentPadding` (visual size matches today’s padded bubbles).

## Call sites

| Surface | Change |
|---------|--------|
| User bubble | Remove outer `Padding`. Pass `contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)`. Move mailbox icon + text row **into** the fade host child so the mask spans the full bubble width. |
| Shell card | Remove outer `Padding(all: 10)`. Pass `contentPadding: EdgeInsets.all(10)`. |
| Edit card | Keep edge-flush; use default / zero `contentPadding`. Line-level padding stays as-is. |

## Tests

Extend `fade_expand_body_test.dart`:

1. Non-zero `contentPadding`: fade strip left/right/bottom align with `AiFadeExpandBody` outer box (no inset from host edges).
2. Existing collapse / expand / selection-dead-zone / hover cases still pass.

Regression (no new geometry asserts required unless a test breaks):

- `user_bubble_fade_expand_test.dart`
- `user_bubble_mailbox_marker_test.dart`
- Shell / edit tool card tests that mount `AiFadeExpandBody`

## Acceptance

- Tall collapsed user bubble: gradient flush to rounded bottom and left/right edges; text still has 16×10 inset.
- Shell card: same flush behavior with 10px content inset.
- Edit card: no visual regression.
- Chevron toggle, selection dead zone, and hover brighten behave as today.
