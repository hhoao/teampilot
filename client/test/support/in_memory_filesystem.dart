import 'package:path/path.dart' as p;
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot_fs/teampilot_fs.dart';

export 'package:teampilot_fs/teampilot_fs.dart' show InMemoryFilesystem;

/// A [HomeStorage] over a native in-memory home rooted at [appDataRoot] —
/// hand to constructor-injected repositories/cubits in tests that do not use
/// [setUpTestAppStorage]. Shares the given [filesystem] so writes through
/// the repository are visible on the same map.
HomeStorage fakeHomeStorage({
  InMemoryFilesystem? filesystem,
  String appDataRoot = '/tp',
  String home = '/home/test',
}) {
  final fs =
      filesystem ??
      InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
  return HomeStorage(
    RuntimeContext(
      target: RuntimeTarget.local(),
      filesystem: fs,
      home: home,
      cwd: home,
      appDataRoot: appDataRoot,
      paths: AppPaths(appDataRoot),
    ),
  );
}
