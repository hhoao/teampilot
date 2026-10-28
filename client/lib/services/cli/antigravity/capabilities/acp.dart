import 'dart:io';

import 'package:acpd/acpd.dart';

import '../../../acp/acp_agent_translator.dart';
import '../../registry/capabilities/acp_capability.dart';

final class AntigravityAcpTranslator extends AcpAgentTranslator {
  const AntigravityAcpTranslator();

  @override
  List<String> get flagCandidates => const [];

  @override
  List<String> get blockingClientMethods => const [];

  @override
  List<String> get notificationClientMethods => const [];

  @override
  String translateStopError(Object error, {required bool suppressAbort}) {
    if (error is RpcError) {
      if (suppressAbort && error.message.contains('aborted')) {
        return acpStopCancelled;
      }
      if (error.code == ErrorCode.authRequired.code ||
          (error.code == -32000 &&
              error.message.contains('Authentication required'))) {
        return acpStopAuthRequired;
      }
      return 'ACP error ${error.code}: ${error.message}';
    }
    return error.toString();
  }
}

final class AntigravityAcpCapability
    implements AcpCapability, AcpOnlyCapability {
  const AntigravityAcpCapability({this.model, this.adapterPath, this.linuxUid});

  final String? model;
  final String? adapterPath;
  final bool? linuxUid;

  bool get _usesUid => linuxUid ?? Platform.isLinux;

  bool get acpOnly => true;

  @override
  String agentExecutable(String cliExecutable) =>
      adapterPath ??
      (Platform.isWindows ? 'agy_acp_server.exe' : 'agy_acp_server.par');

  @override
  List<List<String>> launchArgCandidates(String executable) => [
    // Probe 1.4.3: --uid is a privilege-drop flag, not an account id.
    // Empty disables the switch; a non-empty value must be an existing group.
    if (_usesUid) [executable, '--uid='],
    [executable],
  ];

  @override
  AcpAgentTranslator get translator => const AntigravityAcpTranslator();

  @override
  String? get authenticateMethodId => null;

  @override
  Future<String?> resolveAuthenticateMethodId(Map<String, String> env) async =>
      authenticateMethodId;

  @override
  bool get forwardSessionNewMcpServers => false;

  @override
  Map<String, Object?> sessionNewMeta(Map<String, String> env) => const {};

  @override
  Duration get startupTimeout => const Duration(seconds: 120);

  @override
  Map<String, String> buildEnvironment({
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
  }) {
    final home = '$sessionToolDir/home';
    final env = Map<String, String>.of(baseEnv)
      ..['HOME'] = home
      ..['USERPROFILE'] = home
      ..['GEMINI_HOME'] = '$home/.gemini';
    final m = model?.trim() ?? '';
    if (m.isNotEmpty) env['AGY_ACP_DEFAULT_MODEL'] = m;
    return env;
  }
}
