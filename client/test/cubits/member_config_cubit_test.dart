import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_config_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/cli/member_config/member_config_detail.dart';
import 'package:teampilot/services/cli/member_config/member_config_inspector.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

// Passes explicit non-null deps so the super constructor never reads
// RuntimeStorageContext.current or AppStorage — the fake overrides inspect()
// so none of the injected objects are actually used.
class _FakeInspector extends MemberConfigInspector {
  _FakeInspector(this._result, {this.throwIt = false})
      : super(
          fs: LocalFilesystem(),
          layout: CliDataLayout(
            teampilotRoot: '/tmp/fake',
            fs: LocalFilesystem(),
          ),
          registry: CliToolRegistry(),
        );

  final MemberConfigDetail _result;
  final bool throwIt;

  @override
  Future<MemberConfigDetail> inspect({
    required TeamConfig team,
    required TeamMemberConfig member,
    required String cliTeamName,
  }) async {
    if (throwIt) throw StateError('boom');
    return _result;
  }
}

const _member = TeamMemberConfig(id: 'm1', name: 'Backend');
const _team = TeamConfig(id: 't', name: 'T', cli: CliTool.claude, members: [_member]);

void main() {
  test('emits loading then loaded', () async {
    final cubit = MemberConfigCubit(
      inspector: _FakeInspector(
        const MemberConfigDetail(
          cli: CliTool.claude,
          sourceLayer: MemberConfigSourceLayer.team,
          resolvedDir: '/x',
        ),
      ),
    );
    final states = <MemberConfigStatus>[];
    cubit.stream.listen((s) => states.add(s.status));

    await cubit.load(team: _team, member: _member, cliTeamName: 't-1');

    expect(cubit.state.status, MemberConfigStatus.loaded);
    expect(cubit.state.detail?.resolvedDir, '/x');
    expect(states.first, MemberConfigStatus.loading);
  });

  test('emits error when inspector throws', () async {
    final cubit = MemberConfigCubit(
      inspector: _FakeInspector(
        const MemberConfigDetail(cli: CliTool.claude),
        throwIt: true,
      ),
    );
    await cubit.load(team: _team, member: _member, cliTeamName: 't-1');
    expect(cubit.state.status, MemberConfigStatus.error);
  });
}
