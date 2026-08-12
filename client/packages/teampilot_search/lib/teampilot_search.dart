/// Ripgrep-based content search engine for TeamPilot.
///
/// The Rust core (`rust/`) is compiled into a native asset by
/// `hook/build.dart`; bindings live in
/// `teampilot_search_bindings_generated.dart`.
library;

import 'package:ffi/ffi.dart';

import 'teampilot_search_bindings_generated.dart' as bindings;

/// Version string reported by the Rust core, e.g. `teampilot_search/0.1.0`.
String engineVersion() {
  final ptr = bindings.tp_search_version();
  return ptr.cast<Utf8>().toDartString();
}
