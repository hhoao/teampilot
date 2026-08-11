/// Result of linking a provider's credential path into a shared home.
///
/// Claude-only outcome vocabulary (global `~/.claude` link vs isolated copy);
/// lives in the claude CLI directory per the CLI-architecture convention.
enum CredentialLinkResult { alreadyPresent, linked, copied, missing }
