# Mobile Session History ANR P0 Design

## Goal

Prevent Android input ANRs when opening a session with a large or complex
transcript. Opening a session must remain interactive and show the newest
messages first. Older messages remain available through upward scrolling.

## Evidence and current failure path

The device reports an Android input-dispatch ANR, not a Flutter exception:

- `MainActivity` does not answer a `DOWN` event for 5001 ms.
- The TeamPilot main thread consumes about 98% user CPU while the ANR is
  collected.
- The Dart worker thread is nearly idle.
- The process reaches roughly 791 MB RSS on the reproduced run.

The current history path can still do expensive work on the UI isolate:

1. A page-first miss reads and decodes a suffix window before falling back.
2. The full `AiTranscriptBundle` is sent through `SendPort` as ordinary lists,
   which may deep-copy a large byte payload on the caller isolate.
3. The page miss falls through to a full history load that currently remains
   on the opening path.
4. The history thread can progressively mount the complete loaded data window,
   causing Markdown, tool output, selection, and layout work to accumulate.

The Oplus touch messages are downstream of the blocked main thread and are not
the cause.

## Design

### 1. Transfer transcript bytes without deep copying

Keep `HistoryParseExecutor.parse` as the application-facing boundary. Change
the resident worker protocol so each transcript fragment is represented by
transferable typed bytes plus its name, adapter id, hints, and enrichment
metadata.

The caller converts each fragment to `TransferableTypedData` once and sends a
small transport record. The worker materializes the bytes and reconstructs an
`AiTranscriptBundle` before invoking the existing worker-safe adapter. The
worker response remains an ordinary parsed-message result; response payloads
are bounded by the message window and are not used to send the original raw
transcript back.

The protocol must preserve fragment order, names, byte contents, hints, and
worker enrichment arguments. If a fragment cannot be transferred, the request
fails and the existing non-empty-cache protection keeps the previous view
instead of synchronously parsing the bundle on the UI isolate.

### 2. Remove synchronous large page decoding from the caller isolate

Use the resident JSONL worker for page-first event decoding and logical page
assembly, including windows that are larger than the current synchronous
threshold. The worker request uses the same transferable-byte transport so a
256 KiB or 1 MiB page window does not become a large nested `List<int>` copy.

The page reader continues to own remote range reads and line-boundary
detection. JSON decoding, event-to-message assembly, safety checks, and cursor
metadata are the worker boundary. A worker failure returns the page miss and
lets the loader use its existing safe fallback; it must not reintroduce a large
synchronous decode on Android.

Record the page window byte count and worker decode duration in debug timing
logs so a device run can distinguish remote-read latency from CPU parsing.

### 3. Bound initial mobile widget work

On Android and iOS, the session history thread starts with the newest page and
does not automatically fill the entire loaded message window after first
paint. It mounts only the visible range plus the existing small overscan. As
the user scrolls upward, the viewport mounts the newly visible turns and the
existing `onLoadOlder` pagination loads earlier data.

Mobile must not retain every previously visited turn solely because the user
opened the session. Desktop keeps its existing residency and fill behavior for
this P0.

The newest-page anchor and scroll-to-end behavior remain unchanged. A page
first paint must not be delayed by background full-index completion. If the
page-first attempt misses, the loader immediately publishes the existing
non-empty cache or an empty/loading state and schedules full parsing in the
background; opening the route never awaits that full parse. Existing
pagination, selection, find/reveal, running footer, and scroll-anchor restore
must continue to work.

### 4. Diagnostics and safety

Add low-volume phase diagnostics for:

- page window bytes and decode mode;
- full bundle bytes and transfer mode;
- parse/enrichment worker duration;
- number of messages published to the first frame;
- mobile mounted-turn count during the first few frames.

Do not log message text or raw transcript data. Existing timeout and cache
fallback behavior stays in place. A stale or empty background result must never
replace an already non-empty history.

## Data flow

```text
remote transcript
      |
      +--> range read --> line split --> transferable page decode worker
      |                                      |
      |                                      +--> newest page --> first paint
      |
      +--> full read --> transferable parse worker --> background full index
                                                         |
                                                         +--> cache/pagination

mobile viewport: newest page + visible/overscan turns only
scroll upward: mount visible turns -> request older page when near top
```

## Error handling

- Worker startup, transfer, or request timeout is reported through
  `AppLogger` and treated as a failed background/page attempt.
- No large transcript is synchronously reparsed on the UI isolate as a worker
  failure fallback.
- Existing non-empty history remains visible when a reload yields no messages.
- If a page cannot be safely interpreted because of an unresolved boundary,
  the loader may skip the page and schedule the worker full-index path; it must
  not block the first frame waiting for full parsing.

## Testing

1. Worker transport round-trip preserves multiple fragment names, ordering,
   bytes, and hints.
2. Large transcript parsing sends the transferable worker request and does not
   call the caller-isolate adapter parser.
3. Large page decoding and logical page assembly use the worker path;
   timeout/failure produces a page miss without synchronous large decode.
4. A page-first result publishes the newest messages before the background
   full-index future completes; a page miss publishes cache/loading state
   without awaiting the full-index future.
5. Mobile history thread does not schedule full data-window fill, while the
   desktop path retains existing fill behavior.
6. Existing pagination, scroll-to-end, selection, and non-empty-cache tests
   remain green.

Run focused tests through:

```text
cd client && dart run tool/run_tests.dart <paths/options>
```

Before completion, run the repository-required analyzer and test commands.

## Scope and non-goals

- P0 only: no transcript storage redesign and no server-side indexing.
- No changes to the Android input system or Oplus touch handling.
- No removal of full history; older messages remain loadable by scrolling.
- No desktop performance behavior change in this patch.
- No message-content logging or user-visible diagnostics UI.
