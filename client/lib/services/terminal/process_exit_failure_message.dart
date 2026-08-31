/// Soft cap so a long session does not dump tens of KB into launchError.
const kProcessExitFailureOutputMaxChars = 8 * 1024;

final RegExp _ansiCsi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

/// Builds the launch/process-failure string shown in the session error card.
///
/// Always keeps the exit stub so Retry still has a stable signal, and prepends
/// recent PTY text (e.g. `Error: [unavailable] connect ETIMEDOUT …`) when
/// available — that is what users need under "View details".
String composeProcessExitFailureMessage({
  required int? code,
  String recentOutput = '',
  bool duringStartup = false,
}) {
  final exitLine = _exitStub(code: code, duringStartup: duringStartup);
  final cleaned = _cleanRecentOutput(recentOutput);
  if (cleaned.isEmpty) return exitLine;
  return '$cleaned\n\n$exitLine';
}

String _exitStub({required int? code, required bool duringStartup}) {
  if (duringStartup) {
    return code == 0
        ? '[process exited unexpectedly during startup]'
        : '[process exited with code ${code ?? '?'} during startup]';
  }
  return '[process exited with code ${code ?? '?'}]';
}

String _cleanRecentOutput(String raw) {
  var text = raw.replaceAll(_ansiCsi, '').trim();
  if (text.isEmpty) return '';
  if (text.length <= kProcessExitFailureOutputMaxChars) return text;
  return '…${text.substring(text.length - kProcessExitFailureOutputMaxChars)}';
}
