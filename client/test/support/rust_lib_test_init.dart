import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_alacritty/testing/rust_lib_loader.dart' as rust;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the flutter_alacritty native library for TeamPilot widget/unit tests.
///
/// Uses [rust.resolveRustLibPath] (local build → cargo → precompiled download)
/// but [TestWidgetsFlutterBinding] — not [WidgetsFlutterBinding] — because
/// [flutter_test_config] runs before individual test files.
Future<void> initRustLibForTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final lib = await rust.resolveRustLibPath(
    checkoutRelativeRustDir: _checkoutRustDir,
  );
  await RustLib.init(
    externalLibrary: ExternalLibrary.open(lib),
  );
}

const _checkoutRustDir =
    'packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust';
