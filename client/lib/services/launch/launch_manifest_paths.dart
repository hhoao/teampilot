import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Path context for paths under a work-plane [workTeampilotRoot].
///
/// When the work plane is POSIX (remote SSH/WSL) but [readDelegate] is the
/// Windows control plane, paths must use POSIX separators so SSH flush and SFTP
/// writes land on the remote host correctly.
p.Context workPathContextFor({
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

@Deprecated('Use workPathContextFor')
p.Context manifestPathContextFor({
  required Filesystem readDelegate,
  required String workTeampilotRoot,
}) => workPathContextFor(
  readDelegate: readDelegate,
  workTeampilotRoot: workTeampilotRoot,
);

/// Normalizes [path] for writing on [workFs] (Windows separators → POSIX).
String normalizeWorkPath(Filesystem workFs, String path) {
  if (workFs.pathContext.style == p.Style.posix && path.contains(r'\')) {
    return path.replaceAll(r'\', '/');
  }
  return path;
}

@Deprecated('Use normalizeWorkPath')
String workRelativeKey(Filesystem workFs, String homeRelativeKey) =>
    normalizeWorkPath(workFs, homeRelativeKey);

/// Joins under [ctx] and normalizes for [workFs].
String joinWorkPath(
  Filesystem workFs,
  p.Context ctx,
  String part1, [
  String? part2,
  String? part3,
  String? part4,
  String? part5,
]) {
  var out = part1;
  for (final part in [part2, part3, part4, part5]) {
    if (part == null || part.isEmpty) continue;
    out = ctx.join(out, part);
  }
  return normalizeWorkPath(workFs, out);
}

/// Normalizes launch env values that still contain Windows separators.
Map<String, String> normalizeWorkEnvironment(
  Filesystem workFs,
  Map<String, String> environment,
) {
  if (workFs.pathContext.style != p.Style.posix) return environment;
  return {
    for (final entry in environment.entries)
      entry.key: entry.value.contains(r'\')
          ? normalizeWorkPath(workFs, entry.value)
          : entry.value,
  };
}
