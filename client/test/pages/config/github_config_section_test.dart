import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/github_account_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/github_config_section.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/github/github_credentials_store.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

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

void main() {
  testWidgets('disconnected shows GitHub settings and sign-in', (tester) async {
    final store = GithubCredentialsStore(kv: InMemorySecureKeyValueStore());
    final cubit = _SeededGithubAccountCubit(
      store: store,
      initial: const GithubAccountState(
        status: GithubAccountStatus.disconnected,
        deviceFlowAvailable: true,
      ),
    );
    addTearDown(cubit.close);

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
              child: const GithubConfigWorkspace(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Sign in with GitHub'), findsOneWidget);
  });
}
