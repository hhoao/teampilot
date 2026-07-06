import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Path context for manifest paths under [workTeampilotRoot].
///
/// When the work plane is POSIX (remote SSH/WSL home) but [readDelegate] is the
/// Windows control plane, manifest paths must use POSIX separators so SSH flush
/// and SFTP writes land on the remote host correctly.
p.Context manifestPathContextFor({
  required Filesystem readDelegate,
  required String workTeampilotRoot,
}) {
  final workCtx = AppPaths.pathContextForDataRoot(workTeampilotRoot);
  if (workCtx.style == p.Style.posix &&
      readDelegate.pathContext.style != p.Style.posix) {
    return workCtx;
  }
  return readDelegate.pathContext;
}

/// Normalizes a home-relative key for writing on [workFs] (Windows → POSIX).
String workRelativeKey(Filesystem workFs, String homeRelativeKey) {
  if (workFs.pathContext.style == p.Style.posix &&
      homeRelativeKey.contains(r'\')) {
    return homeRelativeKey.replaceAll(r'\', '/');
  }
  return homeRelativeKey;
}
