import 'package:path/path.dart' as path;

/// Fixture joins for tests that pin [InMemoryFilesystem] to POSIX.
///
/// `package:path`'s top-level `join` follows the host. On Windows that writes
/// a different key than a POSIX filesystem reads back.
final posixPath = path.Context(style: path.Style.posix);
