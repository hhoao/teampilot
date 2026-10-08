import 'package:flutter/widgets.dart';

import '../../../models/ssh_profile.dart';
import '../../../models/team_config.dart';
import '../../io/local_filesystem.dart';
import '../../terminal/terminal_session.dart';

typedef TerminalSessionFactory =
    TerminalSession Function({required String executable, int scrollbackLines});

TerminalSession defaultTerminalSessionFactory({
  required String executable,
  int scrollbackLines = 10000,
}) {
  return TerminalSession(
    executable: executable,
    fs: LocalFilesystem(),
    scrollbackLines: scrollbackLines,
  );
}

typedef PostFrameScheduler = void Function(VoidCallback callback);
typedef SshActiveProfileResolver = SshProfile? Function();
typedef SshProfileByIdResolver = SshProfile? Function(String profileId);
typedef CliExecutableResolver = String Function(CliTool cli);
