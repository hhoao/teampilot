import 'package:flutter_alacritty/testing/rust_lib_loader.dart' as rust;

/// Loads the flutter_alacritty native library for TeamPilot widget/unit tests.
Future<void> initRustLibForTests() => rust.initRustLibForTests(
      checkoutRelativeRustDir: _checkoutRustDir,
    );

const _checkoutRustDir =
    'packages/flutter_alacritty/packages/rust_lib_flutter_alacritty/rust';
