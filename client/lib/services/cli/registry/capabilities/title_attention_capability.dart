import '../cli_capability.dart';

/// Whether the shell should bind a CLI-specific OSC title attention parser.
///
/// Only Cursor returns `true` — it emits `cursor agent` via OSC title codes
/// to signal that agent attention is active.
abstract interface class TitleAttentionCapability implements CliCapability {
  bool get bindTitleAttention;
}
