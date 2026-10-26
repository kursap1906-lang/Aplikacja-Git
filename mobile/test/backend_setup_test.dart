import 'dart:async';

import 'package:copilot_control_center/main.dart';
import 'package:copilot_control_center/src/core/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _signedOut = ApiException('UNAUTHENTICATED', 'Zaloguj się.', 401);
const _outage = ApiException('SERVER_UNAVAILABLE', 'Serwer niedostępny.', 503);

Map<String, dynamic> _session(String login) => {
  'user': {'id': 'setup-owner'},
  'githubAccounts': [
    {
      'id': 'connected-account',
      'login': login,
      'status': 'ACTIVE',
      'scopes': ['read:user', 'repo'],
    },
  ],
};

class _SetupApi extends ApiClient {
  Future<Map<String, dynamic>> Function() session = () async =>
      throw _signedOut;
  ApiException? logoutError;
  ApiException? handoffError;
  Future<void>? handoffPending;
  int checks = 0;
  int forgotten = 0;
  final handoffs = <({String code, String state})>[];

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    if (path == '/session') {
      checks++;
      return session();
    }
    if (path == '/auth/logout') {
      if (logoutError != null) throw logoutError!;
      session = () async => throw _signedOut;
      return {};
    }
    if (path == '/workspace') {
      return {
        'definitions': <Object>[],
        'projects': <Object>[],
        'teams': <Object>[],
      };
    }
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<void> forgetSession() async {
    forgotten++;
  }

  @override
  Future<void> exchangeOAuthHandoff(String code, String state) async {
    handoffs.add((code: code, state: state));
    if (handoffError != null) throw handoffError!;
    await handoffPending;
    session = () async => _session('verified-owner');
  }
}

Widget _app(
  _SetupApi api, {
  String location = 'https://example.test/connect',
}) => ProviderScope(
  overrides: [apiClientProvider.overrideWithValue(api)],
  child: ControlCenterEntry(initialUri: Uri.parse(location)),
);

void main() {
  testWidgets('root requires login instead of opening the demo', (
    tester,
  ) async {
    final api = _SetupApi();
    await tester.pumpWidget(_app(api, location: 'https://example.test/'));
    await tester.pumpAndSettle();

    expect(find.text('Logowanie'), findsOneWidget);
    expect(find.byType(ControlCenterApp), findsNothing);
    expect(api.checks, 1);
  });

  testWidgets('root loads persisted workspace without demonstration data', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => _session('verified-owner');
    await tester.pumpWidget(_app(api, location: 'https://example.test/'));
    await tester.pumpAndSettle();

    expect(find.text('Projekty: 0'), findsOneWidget);
    expect(find.text('Definicje botów: 0'), findsOneWidget);
    expect(find.byType(ControlCenterApp), findsNothing);
    expect(api.checks, 1);
  });

  testWidgets('demo is available only at the explicit demo path', (
    tester,
  ) async {
    final api = _SetupApi();
    await tester.pumpWidget(_app(api, location: 'https://example.test/demo'));
    await tester.pumpAndSettle();

    expect(find.byType(ControlCenterApp), findsOneWidget);
    expect(api.checks, 0);
  });

  testWidgets('setup requires a real session and never mounts sample bots', (
    tester,
  ) async {
    final api = _SetupApi();
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('Logowanie'), findsOneWidget);
    expect(find.text('Połączone konta'), findsNothing);
    expect(find.text('Zespoły AI'), findsNothing);
    expect(api.checks, 1);
    expect(api.forgotten, 1);
  });

  testWidgets('setup displays only the authenticated connected accounts', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => _session('verified-owner');
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('@verified-owner'), findsOneWidget);
    expect(find.text('Połączone · zakres: read:user, repo'), findsOneWidget);
    expect(
      find.textContaining('Panel główny korzysta z danych zapisanych'),
      findsOneWidget,
    );
    expect(find.text('Zespoły AI'), findsNothing);
    expect(api.checks, 1);
  });

  testWidgets('refresh revalidates the session and replaces cached accounts', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => _session('old-owner');
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    api.session = () async => _session('new-owner');
    await tester.tap(find.byTooltip('Odśwież połączenia'));
    await tester.pumpAndSettle();

    expect(find.text('@old-owner'), findsNothing);
    expect(find.text('@new-owner'), findsOneWidget);
    expect(api.checks, 2);
  });

  testWidgets('authenticated setup opens the seed-free API workspace', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => _session('verified-owner');
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Otwórz panel API (beta)'));
    await tester.pumpAndSettle();
    expect(find.text('Projekty: 0'), findsOneWidget);
    expect(find.text('Definicje botów: 0'), findsOneWidget);
    expect(find.text('Tech Lead'), findsNothing);
    expect(
      GoRouter.of(tester.element(find.text('Projekty: 0')))
          .routeInformationProvider
          .value
          .uri
          .path,
      '/workspace',
    );
  });

  testWidgets('logout failure remains visible without clearing the workspace', (
    tester,
  ) async {
    final api = _SetupApi()
      ..session = (() async => _session('verified-owner'))
      ..logoutError = _outage;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();

    expect(find.text('@verified-owner'), findsOneWidget);
    expect(find.textContaining('Serwer niedostępny'), findsOneWidget);
    expect(api.forgotten, 0);
  });

  testWidgets('confirmed logout removes accounts and returns to login', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => _session('verified-owner');
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wyloguj'));
    await tester.pumpAndSettle();

    expect(find.text('@verified-owner'), findsNothing);
    expect(find.text('Logowanie'), findsOneWidget);
    expect(api.forgotten, 1);
  });

  testWidgets(
    'OAuth uses the captured callback URI without the legacy router',
    (tester) async {
      final api = _SetupApi();
      await tester.pumpWidget(
        _app(
          api,
          location: 'https://example.test/auth/complete?code=handoff&state=browser-state',
        ),
      );
      await tester.pumpAndSettle();

      expect(api.handoffs, [(code: 'handoff', state: 'browser-state')]);
      expect(find.text('@verified-owner'), findsOneWidget);
      expect(api.checks, 1);
      expect(
        GoRouter.of(tester.element(find.text('@verified-owner')))
            .routeInformationProvider
            .value
            .uri
            .toString(),
        '/connect',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invalid OAuth link offers a working route back to login', (
    tester,
  ) async {
    final api = _SetupApi();
    await tester.pumpWidget(
      _app(
        api,
        location: 'https://example.test/auth/complete?state=missing-code',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Link logowania jest nieprawidłowy'),
      findsOneWidget,
    );
    expect(api.handoffs, isEmpty);
    await tester.tap(find.text('Wróć do logowania'));
    await tester.pumpAndSettle();
    expect(find.text('Logowanie'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejected OAuth handoff exposes the error and supports retry', (
    tester,
  ) async {
    final api = _SetupApi()..handoffError = _outage;
    await tester.pumpWidget(
      _app(
        api,
        location: 'https://example.test/auth/complete?code=handoff&state=browser-state',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Serwer niedostępny'), findsOneWidget);
    expect(find.text('Połączone konta'), findsNothing);
    await tester.tap(find.text('Wróć do logowania'));
    await tester.pumpAndSettle();
    expect(find.text('Logowanie'), findsOneWidget);
  });

  testWidgets('session outage is not treated as a successful logout', (
    tester,
  ) async {
    final api = _SetupApi()..session = () async => throw _outage;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.textContaining('Serwer niedostępny'), findsOneWidget);
    expect(find.text('Logowanie'), findsNothing);
    expect(api.forgotten, 0);
    api.session = () async => _session('verified-owner');
    await tester.tap(find.text('Sprawdź sesję ponownie'));
    await tester.pumpAndSettle();
    expect(find.text('@verified-owner'), findsOneWidget);
  });

  testWidgets('malformed account data is an error rather than an empty list', (
    tester,
  ) async {
    final api = _SetupApi()
      ..session = () async => {
        'user': {'id': 'setup-owner'},
        'githubAccounts': [null],
      };
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('nieprawidłowe dane obszaru roboczego'),
      findsOneWidget,
    );
    expect(find.text('Nie połączono jeszcze konta GitHub.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving during OAuth exchange does not use a disposed ref', (
    tester,
  ) async {
    final pending = Completer<void>();
    final api = _SetupApi()..handoffPending = pending.future;
    await tester.pumpWidget(
      _app(
        api,
        location: 'https://example.test/auth/complete?code=handoff&state=browser-state',
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
