/// Who runs an edited-message resend.
enum EditExecutor { local, authority }

/// Picks the executor for one seat.
///
/// Delegation needs *both* a connected client role and an authority-owned seat.
/// A seat the phone launched over its own SSH PTY has no desktop runtime, so
/// delegating it would make the desktop spawn a second runtime for the same
/// work tree; a client without a connected panel could not answer the intent.
EditExecutor resolveEditExecutor({
  required bool isClient,
  required bool authorityOwnsSeat,
}) => isClient && authorityOwnsSeat
    ? EditExecutor.authority
    : EditExecutor.local;
