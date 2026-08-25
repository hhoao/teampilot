# Persistent compose drafts

## Goal

Prevent users from losing a typed message when session creation, connection, or
terminal delivery fails, including after the application restarts.

## Scope

The behavior applies independently to both compose surfaces:

- the workspace New Chat landing compose, keyed by workspace ID;
- the compose field of an existing session, keyed by session ID.

## Storage and synchronization

`ComposeDraftCache` remains the in-memory read-through cache used by mounted
widgets.  A small persistent draft store records the same text under the
workspace/session key.  Every non-empty input change writes the current text
directly to that store.  Clearing the field removes the persistent value and
the cache value.

On mounting either compose surface, it restores the current cache value when
available; otherwise it loads its persistent value.  This gives the same draft
back after unmounting a view or restarting the application.

## Submission lifecycle

Submitting a message never clears its draft optimistically.  The draft is
removed only after terminal delivery reports success.  Consequently:

- validation, session-creation, connection, or delivery failures retain it;
- an existing session whose message cannot be delivered retains it;
- reopening the New Chat landing or the session compose after a failure (even
  after restart) restores the text;
- a user who manually empties the field explicitly discards the draft.

Drafts do not become chat-history messages and are not shared between
workspaces or sessions.

## Tests

Add focused regression coverage for the persistent store and both compose
surfaces.  The tests cover persistence/reload, clearing, failed submission
retention, and successful-delivery deletion for landing and existing-session
compose paths.
