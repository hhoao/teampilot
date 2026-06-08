import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/project_profile_cubit.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/project_profile_repository.dart';
import 'package:teampilot/services/plugin/project_plugin_linker_service.dart';
import 'package:teampilot/services/plugin/team_plugin_linker_service.dart';
import 'package:teampilot/services/skill/project_skill_linker_service.dart';
import 'package:teampilot/services/skill/team_skill_linker_service.dart';

void main() {
  late Directory tmp;
  late ProjectProfileRepository repository;
  late _RecordingSkillLinker skillLinker;
  late _RecordingPluginLinker pluginLinker;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('project_profile_cubit_');
    repository = ProjectProfileRepository(rootDir: tmp.path);
    skillLinker = _RecordingSkillLinker();
    pluginLinker = _RecordingPluginLinker();
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  ProjectProfileCubit buildCubit({
    Future<List<Skill>> Function()? installedSkillsLoader,
    Future<List<Plugin>> Function()? installedPluginsLoader,
  }) {
    return ProjectProfileCubit(
      repository: repository,
      skillLinker: skillLinker,
      pluginLinker: pluginLinker,
      installedSkillsLoader:
          installedSkillsLoader ?? () => Future.value(const <Skill>[]),
      installedPluginsLoader:
          installedPluginsLoader ?? () => Future.value(const <Plugin>[]),
    );
  }

  test('load creates and emits profile for project', () async {
    final cubit = buildCubit();
    await cubit.load('proj-1');

    expect(cubit.state.status, ProjectProfileLoadStatus.ready);
    expect(cubit.state.profile?.projectId, 'proj-1');
    expect(cubit.state.profile?.cli, CliTool.claude);

    final onDisk = await repository.load('proj-1');
    expect(onDisk, isNotNull);
    await cubit.close();
  });

  test('setSkillIds persists and triggers skill linker sync', () async {
    final cubit = buildCubit(
      installedSkillsLoader: () => Future.value(const [
        Skill(
          id: 'skill-a',
          name: 'A',
          description: '',
          directory: 'a',
          installedAt: 1,
          updatedAt: 1,
        ),
      ]),
    );
    await cubit.load('proj-2');
    await cubit.setSkillIds(const ['skill-a']);

    expect(cubit.state.profile?.skillIds, ['skill-a']);
    expect(skillLinker.syncCalls, 1);
    expect(skillLinker.lastProjectId, 'proj-2');
    expect(skillLinker.lastSkillIds, ['skill-a']);

    final reloaded = await repository.load('proj-2');
    expect(reloaded?.skillIds, ['skill-a']);
    await cubit.close();
  });

  test('setPluginIds persists and triggers plugin linker sync', () async {
    final cubit = buildCubit(
      installedPluginsLoader: () => Future.value(const [
        Plugin(
          id: 'plugin-a',
          name: 'A',
          description: '',
          directory: 'a',
          version: '1',
          installedAt: 1,
          updatedAt: 1,
        ),
      ]),
    );
    await cubit.load('proj-3');
    await cubit.setPluginIds(const ['plugin-a']);

    expect(cubit.state.profile?.pluginIds, ['plugin-a']);
    expect(pluginLinker.syncCalls, 1);
    expect(pluginLinker.lastProjectId, 'proj-3');
    expect(pluginLinker.lastPluginIds, ['plugin-a']);
    await cubit.close();
  });

  test('setCliDefaults persists effort in map and primary agent', () async {
    final cubit = buildCubit();
    await cubit.load('proj-effort');
    await cubit.setCli(CliTool.claude);
    await cubit.setCliDefaults(
      CliTool.claude,
      provider: 'p1',
      model: 'sonnet',
      effort: 'high',
    );

    expect(cubit.state.profile?.effortsByTool['claude'], 'high');
    expect(cubit.state.profile?.agent.effort, 'high');

    final reloaded = await repository.load('proj-effort');
    expect(reloaded?.effortsByTool['claude'], 'high');
    expect(reloaded?.agent.effort, 'high');
    await cubit.close();
  });

  test('updateAgent and setCli persist without linker sync', () async {
    final cubit = buildCubit();
    await cubit.load('proj-4');
    await cubit.updateAgent(const ProjectAgentConfig(model: 'opus'));
    await cubit.setCli(CliTool.flashskyai);

    expect(skillLinker.syncCalls, 0);
    expect(pluginLinker.syncCalls, 0);
    expect(cubit.state.profile?.agent.model, isEmpty);
    expect(cubit.state.profile?.agent.provider, isEmpty);
    expect(cubit.state.profile?.cli, CliTool.flashskyai);
    await cubit.close();
  });
}

class _RecordingSkillLinker extends ProjectSkillLinkerService {
  _RecordingSkillLinker() : super(appSkillsRoot: '/tmp/skills');

  var syncCalls = 0;
  String? lastProjectId;
  List<String> lastSkillIds = const [];

  @override
  Future<TeamSkillSyncResult> syncForProject({
    required String projectId,
    required List<String> skillIds,
    required List<Skill> installed,
  }) async {
    syncCalls += 1;
    lastProjectId = projectId;
    lastSkillIds = List<String>.from(skillIds);
    return const TeamSkillSyncResult(linked: ['a']);
  }
}

class _RecordingPluginLinker extends ProjectPluginLinkerService {
  _RecordingPluginLinker() : super(appPluginsRoot: '/tmp/plugins');

  var syncCalls = 0;
  String? lastProjectId;
  List<String> lastPluginIds = const [];

  @override
  Future<TeamPluginSyncResult> syncForProject({
    required String projectId,
    required List<String> pluginIds,
    required List<Plugin> installed,
  }) async {
    syncCalls += 1;
    lastProjectId = projectId;
    lastPluginIds = List<String>.from(pluginIds);
    return const TeamPluginSyncResult(linked: ['a']);
  }
}
