import 'package:flutter_alacritty/flutter_alacritty.dart';

/// Drains async [TerminalEngine] PTY batches before reading the mirror grid.
Future<void> flushTerminalEngine(TerminalEngine engine) =>
    engine.drainForTest();
