import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/launch/config_profile_service.dart';
import 'package:teampilot/services/cli/antigravity/capabilities/provider.dart';
import 'package:teampilot/services/cli/antigravity/provider/antigravity_model_catalog.dart';
import 'package:teampilot/services/cli/antigravity/provider_presets.dart';
import 'package:teampilot/services/cli/registry/capabilities/interactive_login_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  group('model catalog', () {
    test('parses agy models output (slug + label per line)', () {
      const output = '''
gemini-4-argon-high       Gemini 4 Argon (High)
gemini-3.8-flash-medium  Gemini 3.8 Flash (Medium)
''';
      expect(AntigravityModelCatalog.parseModels(output), [
        'gemini-4-argon-high',
        'gemini-3.8-flash-medium',
      ]);
    });

    test('parses slug-only lines and ignores blank lines', () {
      expect(
        AntigravityModelCatalog.parseModels(
          '\n  gemini-3.1-pro-high  \n\n  gemini-3.6-flash-high  \n',
        ),
        ['gemini-3.1-pro-high', 'gemini-3.6-flash-high'],
      );
    });

    test('falls back to the documented catalog', () {
      expect(
        AntigravityModelCatalog.fallback,
        containsAll([
          'gemini-4-argon-high',
          'gemini-4-argon-medium',
          'gemini-3.8-flash-high',
          'gemini-3.8-flash-medium',
          'gemini-3.1-pro-high',
        ]),
      );
    });

    test('modelsFor returns the fallback catalog', () {
      expect(
        AntigravityModelCatalog.modelsFor(
          provider: null,
          providerId: 'antigravity',
        ),
        AntigravityModelCatalog.fallback,
      );
    });

    test('live catalog sources may return an empty snapshot', () async {
      const cap = AntigravityProviderCapability();
      final snapshot = await cap.loadFromLiveSources(
        ProviderCatalogLoadContext(
          fs: InMemoryFilesystem(),
          homeDirectory: '/home/test',
        ),
      );
      expect(snapshot.providers, isEmpty);
      expect(cap.catalogSources, isNotEmpty);
      expect(
        cap.catalogSources.single.modelsFor(
          provider: null,
          providerId: 'antigravity',
        ),
        AntigravityModelCatalog.fallback,
      );
    });
  });

  group('presets', () {
    test('offers the Google account and Gemini API key rows only', () {
      expect(
        AntigravityProviderPresets.all.map((preset) => preset.id).toList(),
        ['antigravity', 'gemini-api-key'],
      );
      final official = AntigravityProviderPresets.all.firstWhere(
        (preset) => preset.id == 'antigravity',
      );
      expect(official.template.isOfficial, isTrue);
      expect(official.template.category, AppProviderCategory.official);
      expect(
        official.template.notes.toLowerCase(),
        contains('all antigravity sessions'),
      );
    });
  });

  group('login capability', () {
    test('official rows expose the interactive agy sign-in', () {
      const cap = AntigravityProviderCapability();
      expect(cap, isA<InteractiveCliLoginCapability>());
      expect(cap.loginExecutableName, 'agy');
      expect(cap.loginArguments, isEmpty);

      final official = AntigravityProviderPresets.all.first.template;
      if (!Platform.isAndroid && !Platform.isIOS) {
        expect(cap.appliesTo(official), isTrue);
        final action = cap.actionsFor(official).single;
        expect(action.kind, ProviderCredentialActionKind.login);
        expect(action.primary, isTrue);
        expect(action.showWhenReady, isTrue);
        expect(cap.hidesApiKeyFields(official), isTrue);

        final officialCategory = AppProviderConfig(
          id: 'google-official',
          cli: CliTool.antigravity,
          name: 'Google account',
          category: AppProviderCategory.official,
        );
        expect(cap.appliesTo(officialCategory), isTrue);
        expect(cap.hidesApiKeyFields(officialCategory), isTrue);
      }

      final apiKey = official.copyWith(
        id: 'gemini-api-key',
        isOfficial: false,
        config: const {'authMode': 'gemini-api-key'},
      );
      expect(cap.appliesTo(apiKey), isFalse);
      expect(cap.actionsFor(apiKey), isEmpty);
      expect(cap.hidesApiKeyFields(apiKey), isFalse);
    });

    test(
      'a completed login is recorded and other actions are unsupported',
      () async {
        const cap = AntigravityProviderCapability();
        final result = await cap.execute(
          providerId: 'antigravity',
          kind: ProviderCredentialActionKind.login,
        );
        expect(result.ok, isTrue);
        final revoke = await cap.execute(
          providerId: 'antigravity',
          kind: ProviderCredentialActionKind.revoke,
        );
        expect(revoke.ok, isFalse);
      },
    );
  });

  group('effort', () {
    const cap = AntigravityProviderCapability();

    test('maps low, medium, and high for a chosen model', () {
      expect(cap.isApplicable(model: 'gemini-3.8-flash-high'), isTrue);
      expect(cap.effortCandidates(model: 'gemini-3.8-flash-high'), [
        'low',
        'medium',
        'high',
      ]);
      expect(cap.isApplicable(model: ''), isFalse);
      expect(cap.effortCandidates(model: ''), isEmpty);
    });

    test('only writes an effort the row explicitly pins', () {
      expect(
        cap.defaultEffort(model: 'gemini-3.8-flash-high', provider: null),
        '',
      );
      final pinned = AppProviderConfig(
        id: 'gemini-api-key',
        cli: CliTool.antigravity,
        name: 'Gemini API key',
        config: const {'effort': 'medium'},
      );
      expect(
        cap.defaultEffort(model: 'gemini-3.8-flash-high', provider: pinned),
        'medium',
      );
    });
  });

  group('session home', () {
    late Directory base;
    late LocalFilesystem catalogFs;
    late InMemoryFilesystem homeFs;
    late HomeStorage storage;
    late ConfigProfileService service;

    setUp(() async {
      base = await Directory.systemTemp.createTemp('antigravity_provider_');
      catalogFs = LocalFilesystem();
      homeFs = InMemoryFilesystem();
      storage = fakeHomeStorage(filesystem: homeFs, appDataRoot: base.path);
      service = ConfigProfileService(
        basePath: base.path,
        fs: catalogFs,
        layout: RuntimeLayout(teampilotRoot: base.path, fs: catalogFs),
        storage: storage,
      );
    });

    tearDown(() async {
      if (await base.exists()) await base.delete(recursive: true);
    });

    String runtimeDir({String? memberId}) {
      final member = memberId?.trim() ?? '';
      final root = p.join(
        base.path,
        'workspace',
        'workspaces',
        'workspace-1',
        'sessions',
        'session-1',
        'runtime',
      );
      return member.isEmpty ? root : p.join(root, member);
    }

    String sessionHome({String? memberId}) =>
        p.join(runtimeDir(memberId: memberId), 'antigravity', 'home');

    String cliSettingsPath({String? memberId}) => p.join(
      sessionHome(memberId: memberId),
      '.gemini',
      'antigravity-cli',
      'settings.json',
    );

    String acpSettingsPath({String? memberId}) => p.join(
      sessionHome(memberId: memberId),
      '.gemini',
      'antigravity-acp',
      'settings.json',
    );

    Future<void> writeProviders(Map<String, Object?> providers) async {
      final path = p.join(
        base.path,
        'providers',
        'antigravity',
        'providers.json',
      );
      await catalogFs.ensureDir(p.dirname(path));
      await catalogFs.atomicWrite(path, jsonEncode({'providers': providers}));
    }

    Future<SessionHomeContribution> materialize({
      TeamMemberConfig? member,
      String? memberId,
    }) {
      final scope = resolveLaunchProfileScope(
        workspaceId: 'workspace-1',
        teamId: 'team-a',
        appSessionId: 'session-1',
        cliTeamName: 'session-1',
      );
      return AntigravityProviderCapability(
        storage: storage,
      ).materializeSessionHome(
        sessionHomeContextFromLaunch(
          ConfigProfileLaunchContext(
            workspaceId: 'workspace-1',
            teamId: 'team-a',
            sessionId: scope.sessionId,
            scope: scope,
            member: member,
            members: [if (member != null) member],
            memberId: memberId,
            workingDirectory: '/workspace/workspace',
            paths: service,
            catalog: service,
          ),
          CliTool.antigravity,
        ),
      );
    }

    Future<Map<String, Object?>> readJson(String path) async =>
        (jsonDecode((await catalogFs.readString(path))!))
            as Map<String, Object?>;

    test('official account writes oauth-personal with no env', () async {
      final contribution = await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'antigravity',
          model: 'gemini-3.8-flash-high',
        ),
      );

      expect(contribution.environment, isEmpty);
      expect(contribution.environment.containsKey('HOME'), isFalse);
      final cli = await readJson(cliSettingsPath());
      expect(cli['model'], 'gemini-3.8-flash-high');
      expect(cli.containsKey('modelProvider'), isFalse);
      final acp = await readJson(acpSettingsPath());
      expect(acp['auth'], {'type': 'oauth-personal'});
    });

    test('mixed-mode launch returns the member-scoped HOME hint', () async {
      final contribution = await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'antigravity',
          model: 'gemini-3.8-flash-high',
        ),
        memberId: 'm1',
      );

      final toolDir = p.join(runtimeDir(memberId: 'm1'), 'antigravity');
      expect(contribution.environment['HOME'], toolDir);
      expect(contribution.environment.containsKey('GEMINI_API_KEY'), isFalse);

      final cli = await readJson(cliSettingsPath(memberId: 'm1'));
      expect(cli['model'], 'gemini-3.8-flash-high');
      final acp = await readJson(acpSettingsPath(memberId: 'm1'));
      expect(acp['auth'], {'type': 'oauth-personal'});
    });

    test(
      'official category without isOfficial maps to oauth-personal',
      () async {
        await writeProviders({
          'google-official': {
            'id': 'google-official',
            'cli': 'antigravity',
            'name': 'Google account',
            'category': 'official',
            'isOfficial': false,
          },
        });

        final contribution = await materialize(
          member: const TeamMemberConfig(
            id: 'm1',
            name: 'Member',
            provider: 'google-official',
          ),
        );

        expect(contribution.environment, isEmpty);
        final cli = await readJson(cliSettingsPath());
        expect(cli.containsKey('modelProvider'), isFalse);
        final acp = await readJson(acpSettingsPath());
        expect(acp['auth'], {'type': 'oauth-personal'});
      },
    );

    test('Gemini API key maps to gemini-api-key and GEMINI_API_KEY', () async {
      await writeProviders({
        'gemini-api-key': {
          'id': 'gemini-api-key',
          'cli': 'antigravity',
          'name': 'Gemini API key',
          'apiKey': 'sk-secret',
          'baseUrl': 'https://generativelanguage.example.test',
          'defaultModel': 'gemini-3.8-flash-medium',
          'category': 'custom',
          'config': {'authMode': 'gemini-api-key'},
        },
      });

      final contribution = await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'gemini-api-key',
        ),
      );

      expect(contribution.environment, {
        'GEMINI_API_KEY': 'sk-secret',
        'GOOGLE_GEMINI_BASE_URL': 'https://generativelanguage.example.test',
      });
      final cliText = (await catalogFs.readString(cliSettingsPath()))!;
      expect(cliText, isNot(contains('sk-secret')));
      final cli = jsonDecode(cliText) as Map<String, Object?>;
      expect(cli['model'], 'gemini-3.8-flash-medium');
      expect(cli['modelProvider'], 'gemini');
      final acp = await readJson(acpSettingsPath());
      expect(acp['auth'], {'type': 'gemini-api-key'});
    });

    test('ADC maps to agent-platform with project and location env', () async {
      await writeProviders({
        'agent-platform': {
          'id': 'agent-platform',
          'cli': 'antigravity',
          'name': 'Google Cloud ADC',
          'category': 'cloud_provider',
          'config': {
            'authMode': 'agent-platform',
            'project': 'my-project',
            'location': 'europe-west4',
          },
        },
      });

      final contribution = await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'agent-platform',
        ),
      );

      expect(contribution.environment, {
        'AGY_ADC_AUTH': 'true',
        'GOOGLE_CLOUD_PROJECT': 'my-project',
        'GOOGLE_CLOUD_LOCATION': 'europe-west4',
      });
      final acp = await readJson(acpSettingsPath());
      expect(acp['auth'], {'type': 'agent-platform'});
      final cli = await readJson(cliSettingsPath());
      expect(cli.containsKey('modelProvider'), isFalse);
    });

    test('ADC without project/location only enables AGY_ADC_AUTH', () async {
      await writeProviders({
        'adc': {
          'id': 'adc',
          'cli': 'antigravity',
          'name': 'ADC',
          'category': 'cloud_provider',
          'config': {'authMode': 'agent-platform'},
        },
      });

      final contribution = await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'adc',
        ),
      );

      expect(contribution.environment, {'AGY_ADC_AUTH': 'true'});
    });

    test('merges into existing settings without clobbering keys', () async {
      await catalogFs.ensureDir(p.dirname(cliSettingsPath()));
      await catalogFs.ensureDir(p.dirname(acpSettingsPath()));
      await catalogFs.atomicWrite(
        cliSettingsPath(),
        jsonEncode({
          'theme': 'dark',
          'permissions': {
            'allow': ['ls'],
          },
        }),
      );
      await catalogFs.atomicWrite(
        acpSettingsPath(),
        jsonEncode({
          'auth': {'type': 'gemini-api-key', 'extra': 'keep'},
          'telemetry': false,
        }),
      );

      await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'antigravity',
          model: 'gemini-3.7-flash-high',
        ),
      );

      final cli = await readJson(cliSettingsPath());
      expect(cli['model'], 'gemini-3.7-flash-high');
      expect(cli['theme'], 'dark');
      expect(cli['permissions'], {
        'allow': ['ls'],
      });

      final acp = await readJson(acpSettingsPath());
      expect(acp['auth'], {'type': 'oauth-personal', 'extra': 'keep'});
      expect(acp['telemetry'], isFalse);
    });

    test('switching back to the official row drops modelProvider', () async {
      await writeProviders({
        'antigravity': {
          'id': 'antigravity',
          'cli': 'antigravity',
          'name': 'Google account',
          'isOfficial': true,
          'category': 'official',
          'config': {'authMode': 'oauth-personal'},
        },
        'gemini-api-key': {
          'id': 'gemini-api-key',
          'cli': 'antigravity',
          'name': 'Gemini API key',
          'apiKey': 'sk-secret',
          'config': {'authMode': 'gemini-api-key'},
        },
      });
      await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'gemini-api-key',
        ),
      );
      expect((await readJson(cliSettingsPath()))['modelProvider'], 'gemini');

      await materialize(
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'Member',
          provider: 'antigravity',
        ),
      );
      final cli = await readJson(cliSettingsPath());
      expect(cli.containsKey('modelProvider'), isFalse);
      expect((await readJson(acpSettingsPath()))['auth'], {
        'type': 'oauth-personal',
      });
    });
  });
}
