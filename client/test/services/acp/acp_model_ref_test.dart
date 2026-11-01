import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/acp/acp_model_ref.dart';
import 'package:teampilot/services/acp/acp_session.dart';

void main() {
  const unique = AcpModelState(
    configId: 'model',
    currentId: 'opencode/flint-40b-free',
    options: [
      AcpModelOption(id: 'opencode/flint-40b-free', name: 'Flint'),
      AcpModelOption(
        id: 'opencode-go/deepseek-v4.1-flash',
        name: 'Go Flash',
      ),
      AcpModelOption(
        id: 'opencode/deepseek-v4.1-flash-free',
        name: 'Zen Flash Free',
      ),
    ],
  );

  const dual = AcpModelState(
    configId: 'model',
    currentId: 'opencode/hy3',
    options: [
      AcpModelOption(id: 'opencode/hy3', name: 'Zen Hy3'),
      AcpModelOption(id: 'opencode-go/hy3', name: 'Go Hy3'),
    ],
  );

  group('acpModelIdForLaunchRef', () {
    test('uses an exact advertised id', () {
      expect(
        acpModelIdForLaunchRef(
          state: unique,
          provider: '',
          model: 'opencode-go/deepseek-v4.1-flash',
        ),
        'opencode-go/deepseek-v4.1-flash',
      );
    });

    test('qualifies a bare id with the provider namespace', () {
      expect(
        acpModelIdForLaunchRef(
          state: unique,
          provider: 'opencode-go',
          model: 'deepseek-v4.1-flash',
        ),
        'opencode-go/deepseek-v4.1-flash',
      );
    });

    test('falls back to a unique suffix match', () {
      expect(
        acpModelIdForLaunchRef(
          state: unique,
          provider: '',
          model: 'deepseek-v4.1-flash',
        ),
        'opencode-go/deepseek-v4.1-flash',
      );
    });

    test('leaves an ambiguous bare id unresolved', () {
      expect(
        acpModelIdForLaunchRef(state: dual, provider: '', model: 'hy3'),
        isNull,
      );
      expect(
        acpModelIdForLaunchRef(
          state: dual,
          provider: 'opencode-go',
          model: 'hy3',
        ),
        'opencode-go/hy3',
      );
    });

    test('an explicit namespace never falls back to the other layer', () {
      expect(
        acpModelIdForLaunchRef(
          state: unique,
          provider: 'opencode',
          model: 'deepseek-v4.1-flash',
          allowSuffix: false,
        ),
        isNull,
      );
      // A persisted bare ref may still resolve via a unique suffix.
      expect(
        acpModelIdForLaunchRef(
          state: unique,
          provider: 'opencode',
          model: 'deepseek-v4.1-flash',
        ),
        'opencode-go/deepseek-v4.1-flash',
      );
    });
  });

  group('acpPersistedModelRef', () {
    test('keeps a unique catalog id bare', () {
      expect(
        acpPersistedModelRef(
          state: unique,
          namespace: 'opencode-go',
          model: 'deepseek-v4.1-flash',
        ),
        'deepseek-v4.1-flash',
      );
    });

    test('qualifies an id that exists in both namespaces', () {
      expect(
        acpPersistedModelRef(
          state: dual,
          namespace: 'opencode-go',
          model: 'hy3',
        ),
        'opencode-go/hy3',
      );
    });

    test('always keeps the namespace for a custom id', () {
      expect(
        acpPersistedModelRef(
          state: unique,
          namespace: 'opencode-go',
          model: 'company/internal-model',
          catalogModel: false,
        ),
        'opencode-go/company/internal-model',
      );
    });
  });
}
