import 'package:path/path.dart' as p;

import '../cli/registry/config_profile/config_profile_context.dart';
import '../io/filesystem.dart';
import 'launch_manifest_paths.dart';

export 'launch_manifest_paths.dart';

/// Work-plane path helpers for [ConfigProfileDelegate] (session runtime writes).
extension WorkPlanePaths on ConfigProfileDelegate {
  p.Context get workPathContext => workPathContextFor(
    readDelegate: fs,
    workTeampilotRoot: basePath,
  );

  String joinWork(
    String part1, [
    String? part2,
    String? part3,
    String? part4,
    String? part5,
  ]) => joinWorkPath(fs, workPathContext, part1, part2, part3, part4, part5);

  String normalizeWork(String path) => normalizeWorkPath(fs, path);
}

/// Launch-time work-plane helpers on [ConfigProfileLaunchContext].
extension WorkPlaneLaunchContext on ConfigProfileLaunchContext {
  p.Context get workPathContext => paths.workPathContext;

  String joinWork(
    String part1, [
    String? part2,
    String? part3,
    String? part4,
    String? part5,
  ]) => paths.joinWork(part1, part2, part3, part4, part5);

  String normalizeWork(String path) => paths.normalizeWork(path);
}

/// Normalizes a path before direct SFTP / work-fs writes (non-manifest).
Future<void> writeWorkString(
  Filesystem workFs,
  String path,
  String content,
) async {
  await workFs.writeString(normalizeWorkPath(workFs, path), content);
}

Future<void> writeWorkBytes(
  Filesystem workFs,
  String path,
  List<int> bytes,
) async {
  await workFs.writeBytes(normalizeWorkPath(workFs, path), bytes);
}

Future<void> ensureWorkDir(Filesystem workFs, String path) async {
  await workFs.ensureDir(normalizeWorkPath(workFs, path));
}
