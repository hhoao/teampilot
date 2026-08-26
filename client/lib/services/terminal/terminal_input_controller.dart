import 'dart:convert';
import 'dart:typed_data';

import 'terminal_fullscreen_input_channel.dart';
import 'terminal_input_command_queue.dart';
import 'terminal_launch_controller.dart';
import '../workspace_dnd/terminal_text_sink.dart';

/// PTY write and full-screen TUI input operations for a connected session.
///
/// ISP: callers that inject stdin depend on this narrow surface, not
/// [TerminalSession] lifecycle or display state.
final class TerminalInputController implements TerminalTextSink {
  TerminalInputController({
    required TerminalLaunchController launch,
    required void Function() onTurnStart,
    required Duration Function() defaultFullscreenSettleDelay,
    TerminalFullscreenInputChannel? fullscreen,
    TerminalInputCommandQueue? commands,
  }) : _launch = launch,
       _onTurnStart = onTurnStart,
       _defaultFullscreenSettleDelay = defaultFullscreenSettleDelay {
    _commands =
        commands ??
        TerminalInputCommandQueue(
          write: (text) => launch.writeToPty(Uint8List.fromList(utf8.encode(text))),
        );
    _fullscreen = fullscreen ?? TerminalFullscreenInputChannel(commands: _commands);
  }

  final TerminalLaunchController _launch;
  final void Function() _onTurnStart;
  final Duration Function() _defaultFullscreenSettleDelay;
  late final TerminalInputCommandQueue _commands;
  late final TerminalFullscreenInputChannel _fullscreen;

  static const fullScreenSubmitDelay =
      TerminalFullscreenInputChannel.fullScreenSubmitDelay;

  void writeToPty(String text) =>
      _launch.writeToPty(Uint8List.fromList(utf8.encode(text)));

  @override
  void appendText(String text) => writeToPty(text);

  @override
  Future<void> pasteWithoutSubmit(String text) => pasteText(text);

  Future<void> pasteText(String text, {bool Function()? canExecute}) =>
      _fullscreen.pasteText(text, canExecute: canExecute);

  Future<void> clearInputLine() => _fullscreen.clearInputLine();

  Future<void> clearStagedInput({
    int killLines = 3,
    bool Function()? canExecute,
  }) => _fullscreen.clearStagedInput(
    killLines: killLines,
    canExecute: canExecute,
  );

  void writeln(String text) =>
      _fullscreen.writeln(text, onTurnStart: _onTurnStart);

  Future<void> submitFullScreenInput(
    String text, {
    Duration? pasteSettleDelay,
    bool Function()? canExecute,
  }) {
    return _fullscreen.submitFullScreenInput(
      text,
      pasteSettleDelay: pasteSettleDelay,
      defaultSettleDelay: pasteSettleDelay ?? _defaultFullscreenSettleDelay(),
      onTurnStart: _onTurnStart,
      canExecute: canExecute,
    );
  }

  Future<void> submitPendingCr({bool Function()? canExecute}) =>
      _fullscreen.submitPendingCr(canExecute: canExecute);
}
