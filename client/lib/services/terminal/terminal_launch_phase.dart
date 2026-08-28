/// PTY attach → confirm → running. See [onPtyOutput] and [_confirmProcessStarted].
enum TerminalLaunchPhase { idle, spawning, confirming, running, failed }
