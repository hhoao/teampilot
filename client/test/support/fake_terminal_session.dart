import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/team_bus/bus_user_line_capture.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

/// Recording [TerminalSession] for cubit / smoke tests that assert connect args.
class FakeTerminalSession extends TerminalSession {
  FakeTerminalSession({
    super.executable = 'flashskyai',
    super.scrollbackLines = 10000,
  });

  var _running = false;
  final connectedMembers = <String>[];
  final resumedSessions = <String>[];
  final lastFixedSessionIds = <String?>[];
  final lastResumeSessionIds = <String?>[];
  final lastAdditionalDirectoriesLists = <List<String>>[];
  final lastExtraEnvironments = <Map<String, String>?>[];

  @override
  bool get isRunning => _running;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    ShellLaunchSpec? shellLaunch,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    BusUserInputRouting? busUserInputRouting,
    String? executableOverride,
    TerminalObservationAttach? observation,
  }) {
    lastFixedSessionIds.add(fixedSessionId);
    lastResumeSessionIds.add(resumeSessionId);
    lastAdditionalDirectoriesLists.add(
      List<String>.from(
        shellLaunch?.launchContext.additionalDirectories ??
            additionalDirectories,
      ),
    );
    lastExtraEnvironments.add(
      extraEnvironment == null
          ? null
          : Map<String, String>.from(extraEnvironment),
    );
    _running = true;
    if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
      resumedSessions.add(resumeSessionId);
    }
    final member = shellLaunch?.launchContext.member;
    if (member != null) {
      connectedMembers.add(member.id);
    }
    onProcessStarted?.call();
  }

  @override
  void disconnect() {
    _running = false;
  }

  @override
  void dispose() {
    _running = false;
  }
}
