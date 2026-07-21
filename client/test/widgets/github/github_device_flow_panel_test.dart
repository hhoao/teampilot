import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/github_account_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/theme/app_typography_scale.dart';
import 'package:teampilot/widgets/github/github_device_flow_panel.dart';

class InMemorySecureKeyValueStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _SeededGithubAccountCubit extends GithubAccountCubit {
  _SeededGithubAccountCubit({
    required GithubCredentialsStore store,
    required GithubAccountState initial,
  }) : super(
         store: store,
         deviceFlow: null,
         openUrl: (_) async {},
         fetchLogin: (_) async => 'octocat',
         deviceFlowAvailable: initial.deviceFlowAvailable,
       ) {
    emit(initial);
  }
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required GithubAccountCubit cubit,
  bool showDisconnect = true,
}) async {
  final theme = ThemeData(useMaterial3: true);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: theme,
      home: TpTheme(
        data: TpThemeData.fromColorScheme(
          theme.colorScheme,
          scale: 1.0,
          controlScale: AppTypographyScale.standard.multiplier,
        ),
        child: Scaffold(
          body: BlocProvider<GithubAccountCubit>.value(
            value: cubit,
            child: GithubDeviceFlowPanel(showDisconnect: showDisconnect),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('GithubDeviceFlowPanel', () {
    testWidgets('disconnected shows sign-in button', (tester) async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final cubit = _SeededGithubAccountCubit(
        store: store,
        initial: const GithubAccountState(
          status: GithubAccountStatus.disconnected,
          deviceFlowAvailable: true,
        ),
      );
      addTearDown(cubit.close);

      await _pumpPanel(tester, cubit: cubit);

      expect(find.byKey(const Key('github-sign-in')), findsOneWidget);
      expect(find.text('Sign in with GitHub'), findsOneWidget);
    });

    testWidgets('waiting shows user code and verification uri', (tester) async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final cubit = _SeededGithubAccountCubit(
        store: store,
        initial: const GithubAccountState(
          status: GithubAccountStatus.waiting,
          userCode: 'ABCD-1234',
          verificationUri: 'https://github.com/login/device?user_code=ABCD-1234',
          deviceFlowAvailable: true,
        ),
      );
      addTearDown(cubit.close);

      await _pumpPanel(tester, cubit: cubit);

      expect(find.byKey(const Key('github-user-code')), findsOneWidget);
      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(find.byKey(const Key('github-verification-uri')), findsOneWidget);
      expect(
        find.text('https://github.com/login/device?user_code=ABCD-1234'),
        findsOneWidget,
      );
    });

    testWidgets('connected shows disconnect when showDisconnect is true', (
      tester,
    ) async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final cubit = _SeededGithubAccountCubit(
        store: store,
        initial: const GithubAccountState(
          status: GithubAccountStatus.connected,
          login: 'octocat',
          source: GithubCredentialSource.oauth,
          deviceFlowAvailable: true,
        ),
      );
      addTearDown(cubit.close);

      await _pumpPanel(tester, cubit: cubit, showDisconnect: true);

      expect(find.byKey(const Key('github-disconnect')), findsOneWidget);
      expect(find.text('Connected as @octocat'), findsOneWidget);
    });

    testWidgets('connected hides disconnect when showDisconnect is false', (
      tester,
    ) async {
      final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
      final cubit = _SeededGithubAccountCubit(
        store: store,
        initial: const GithubAccountState(
          status: GithubAccountStatus.connected,
          login: 'octocat',
          deviceFlowAvailable: true,
        ),
      );
      addTearDown(cubit.close);

      await _pumpPanel(tester, cubit: cubit, showDisconnect: false);

      expect(find.byKey(const Key('github-disconnect')), findsNothing);
    });
  });
}
