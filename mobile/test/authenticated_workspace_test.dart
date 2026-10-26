import 'dart:async';

import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/core/providers.dart';
import 'package:copilot_control_center/src/features/auth/authenticated_workspace_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _alice = <String, dynamic>{
  'user': {'id': 'alice', 'email': 'alice@example.test'},
  'githubAccounts': <Object>[],
};
const _bob = <String, dynamic>{
  'user': {'id': 'bob', 'email': 'bob@example.test'},
  'githubAccounts': <Object>[],
};
const _unauthenticated = ApiException('UNAUTHENTICATED', 'Zaloguj się.', 401);
const _unavailable = ApiException(
  'SERVER_UNAVAILABLE',
  'Serwer niedostępny.',
  503,
);

class _SessionApi extends ApiClient {
  Future<Map<String, dynamic>> Function() session = () async => _alice;
  ApiException? logoutFailure;
  final requests = <({String path, String method, bool credentials})>[];
  int forgotten = 0;
  int localTokenReads = 0;
  int signIns = 0;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    requests.add((path: path, method: method, credentials: withCredentials));
    if (path == '/session') return session();
    if (path == '/auth/logout') {
      if (logoutFailure != null) throw logoutFailure!;
      session = () async => throw _unauthenticated;
      return {};
    }
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<String?> currentSession() async {
    ++localTokenReads;
    return 'expired-local-token';
  }

  @override
  Future<void> forgetSession() async => ++forgotten;

  @override
  Future<void> signIn({required String email, required String password}) async {
    ++signIns;
    session = () async => _bob;
  }
}

final _privateData = FutureProvider<String>((ref) async {
  final session = await ref.watch(sessionDataProvider.future);
  return (session['user'] as Map)['id'] as String;
});

class _Workspace extends ConsumerStatefulWidget {
  const _Workspace({required this.logout});

  final Future<void> Function() logout;

  @override
  ConsumerState<_Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends ConsumerState<_Workspace> {
  String? error;

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(_privateData);
    return Scaffold(
      body: Column(
        children: [
          Text(
            owner.when(
              data: (value) => 'Private workspace: $value',
              error: (error, stack) => error.toString(),
              loading: () => 'Loading',
            ),
          ),
          if (error != null) Text(error!),
          TextButton(
            onPressed: () async {
              try {
                await widget.logout();
              } on ApiException catch (failure) {
                if (mounted) setState(() => error = failure.toString());
              }
            },
            child: const Text('Wyloguj'),
          ),
        ],
      ),
    );
  }
}

Widget _app(_SessionApi api) => ProviderScope(
  overrides: [apiClientProvider.overrideWithValue(api)],
  child: MaterialApp(
    home: AuthenticatedWorkspaceGate(
      builder: (context, session, logout) => _Workspace(logout: logout),
    ),
  ),
);

void main() {
  test(
    'expired local token cannot authenticate without server validation',
    () async {
      final api = _SessionApi()..session = () async => throw _unauthenticated;
      final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      expect(await container.read(sessionProvider.future), isFalse);
      expect(api.forgotten, 1);
      expect(api.localTokenReads, 0);
      expect(api.requests.single.path, '/session');
      expect(api.requests.single.credentials, isTrue);
    },
  );

  test('server outage is not mistaken for a signed-out session', () async {
    final api = _SessionApi()..session = () async => throw _unavailable;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(sessionProvider.future),
      throwsA(
        isA<ApiException>().having(
          (error) => error.code,
          'code',
          'SERVER_UNAVAILABLE',
        ),
      ),
    );
    expect(api.forgotten, 0);
  });

  test(
    'session response must contain user identity and connected account list',
    () async {
      final api = _SessionApi();
      for (final response in <Map<String, dynamic>>[
        {},
        {
          'user': {'id': ''},
          'githubAccounts': [],
        },
        {
          'user': {'id': 42},
          'githubAccounts': [],
        },
        {
          'user': {'id': 'alice'},
        },
      ]) {
        api.session = () async => response;
        await expectLater(
          api.loadSession(),
          throwsA(
            isA<ApiException>().having(
              (error) => error.code,
              'code',
              'INVALID_SESSION_RESPONSE',
            ),
          ),
        );
      }
    },
  );

  testWidgets('workspace is not mounted before server verifies the session', (
    tester,
  ) async {
    final result = Completer<Map<String, dynamic>>();
    final api = _SessionApi()..session = () => result.future;
    await tester.pumpWidget(_app(api));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(_Workspace), findsNothing);

    result.complete(_alice);
    await tester.pumpAndSettle();
    expect(find.text('Private workspace: alice'), findsOneWidget);
    expect(api.requests, hasLength(1));
  });

  testWidgets('expired session shows login instead of private content', (
    tester,
  ) async {
    final api = _SessionApi()..session = () async => throw _unauthenticated;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Zaloguj się'), findsOneWidget);
    expect(find.byType(_Workspace), findsNothing);
    expect(api.forgotten, 1);
  });

  testWidgets('server outage offers retry without deleting credentials', (
    tester,
  ) async {
    final api = _SessionApi()..session = () async => throw _unavailable;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Serwer niedostępny.'), findsOneWidget);
    expect(find.text('Zaloguj się'), findsNothing);
    expect(api.forgotten, 0);

    api.session = () async => _alice;
    await tester.tap(find.text('Sprawdź sesję ponownie'));
    await tester.pumpAndSettle();
    expect(find.text('Private workspace: alice'), findsOneWidget);
  });

  testWidgets('failed logout keeps private workspace and shows the error', (
    tester,
  ) async {
    final api = _SessionApi()..logoutFailure = _unavailable;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.text('Private workspace: alice'), findsOneWidget);
    expect(find.text('Serwer niedostępny.'), findsOneWidget);
    expect(api.forgotten, 0);
  });

  testWidgets('another login cannot reuse the previous user provider cache', (
    tester,
  ) async {
    final api = _SessionApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Private workspace: alice'), findsOneWidget);
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();
    expect(find.byType(_Workspace), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adres e-mail'),
      'bob@example.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hasło'),
      'a-valid-test-password',
    );
    await tester.ensureVisible(find.text('Zaloguj się'));
    await tester.tap(find.text('Zaloguj się'));
    await tester.pumpAndSettle();
    expect(api.signIns, 1);
    expect(find.text('Private workspace: bob'), findsOneWidget);
    expect(find.text('Private workspace: alice'), findsNothing);
    expect(
      api.requests.where((request) => request.path == '/session'),
      hasLength(2),
    );
  });

  testWidgets('unmounted gate ignores an in-flight session response', (
    tester,
  ) async {
    final result = Completer<Map<String, dynamic>>();
    final api = _SessionApi()..session = () => result.future;
    await tester.pumpWidget(_app(api));
    await tester.pumpWidget(const MaterialApp(home: Text('Disposed')));
    result.complete(_alice);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Disposed'), findsOneWidget);
  });
}
