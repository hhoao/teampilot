import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/pages/chat/acp_runtime_scope.dart';
import 'package:teampilot/services/cli/registry/capabilities/native_command_capability.dart';

void main() {
  test('projects available commands into the scope snapshot', () {
    const commands = [
      NativeCommand(name: 'deploy', descriptionText: 'Deploy the app'),
    ];
    final state = AcpChatRuntimeState(availableCommands: commands);

    final ui = AcpRuntimeUiState.of(state);

    expect(ui.availableCommands, commands);
    expect(ui, AcpRuntimeUiState.of(state));
  });
}
