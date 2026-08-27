# Persisted failed message history

## Goal

When a message submitted from an existing session cannot be delivered, keep it
in that session's chat history as a failed outgoing message instead of moving
it back into the compose field. The failed message must remain visible after
the app restarts.

## Behavior

- On submit, append a local user-message record with `sending` status.
- If terminal delivery succeeds, finalize the record as a normal user message.
- If delivery fails, retain the original text with `failed` status and leave
  the compose field empty.
- A failed record offers `Retry` and `Edit and retry` actions.
- `Retry` submits the original text again; success finalizes it, failure keeps
  it failed.
- `Edit and retry` loads the original text into the compose field and lets the
  user change it before submitting.
- Records are persisted per session and restored into the session history after
  an app restart.
- New Chat has no session to own a record before creation. If session creation
  fails, keep the text visible on the New Chat landing; once a session exists,
  the message follows the existing-session behavior.

## Storage and boundaries

Store failed-message records in a local file under the session directory; do
not write them into any CLI transcript. Each record contains a stable local ID,
session ID, message text, status, and creation/update timestamps. The store is
independent of compose drafts: drafts protect text before submission, while
failed records represent a submitted message.

## State flow

```text
compose submit
  -> persist sending record
  -> clear compose field
  -> deliver to terminal
       -> success: persist sent status / remove pending marker
       -> failure: persist failed status and render retry actions
```

## Testing

Add tests for sending/failed/success state transitions, retry success and
failure, edit-and-retry text loading, persistence across a fresh store/session
instance, and isolation between sessions. Existing draft tests remain to verify
pre-submit launch failures retain drafts.
