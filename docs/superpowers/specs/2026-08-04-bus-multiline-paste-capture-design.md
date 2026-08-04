# Bus multiline paste capture (parked mixed seats)

## Problem

When a mixed-team member is parked on `wait_for_message`, `BusUserLineCapture` treats every `\r`/`\n` as a submit. Pasting a multi-line “Copy as cURL” (or any multi-line blob) therefore enqueues **one TeamBus mail per line**, and the parked/queued UI shows many envelope bubbles.

## Decision

**Paste inserts; Enter submits** (terminal + bracketed-paste semantics).

| Input | Behavior |
|-------|----------|
| Bracketed paste (`ESC[200~` … `ESC[201~`) | Newlines are **content** (normalized to `\n`). No `onUserLine`, no Ctrl-U. Bytes still pass through for CLI echo. |
| Enter after paste / normal typing | One `onUserLine` with the full buffer (may contain `\n`) + one Ctrl-U while intercepting. |
| Non-bracketed multi-line chunk in one `filter()` call | Internal newlines are content; a trailing line ending at end of that call submits **once** with the joined body (fallback when the CLI did not enable bracketed paste). |
| Separate Enter keystrokes in separate `filter()` calls | Still one mail per Enter (unchanged). |

## Out of scope / unchanged

- `FirstUserLineCapture` / `EveryUserLineCapture`: title / turn-start probes, not bus mail. Leave as line-oriented.
- History compose → `deliverUserCommand`: already sends the whole string as one mail.
- `TeamBus.deliverUserCommand` API: already accepts multi-line `content`.

## Consistency

Parked terminal paste and History compose both yield **one** queued mail for one user intent (one paste+Enter, or one compose send).

## Tests

Extend `bus_user_line_capture_test.dart`:

1. Bracketed multi-line paste does not submit until trailing Enter; one mail with embedded `\n`.
2. Existing single-line Enter + Ctrl-U still holds.
3. Non-bracketed multi-line single chunk → one submit.
4. Two separate `\r` submissions in two `filter()` calls → two submits.
5. UTF-8 / backspace regressions still pass.
