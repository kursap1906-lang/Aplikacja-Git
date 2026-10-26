import 'dart:async';

import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/auth/backend_workspace_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _definition(String id, String name) => {
  'id': id,
  'name': name,
  'role': '$name role',
  'description': '$name duties',
  'systemPrompt': '$name prompt',
  'skills': ['testing'],
};

class _WorkspaceApi extends ApiClient {
  final definitions = <Map<String, dynamic>>[];
  final writes = <({String path, String method, Map<String, dynamic> body})>[];
  Completer<void>? sessionPending;
  Completer<void>? savePending;
  ApiException? loadError;
  ApiException? saveError;
  bool authenticated = true;
  int loads = 0;
  int created = 0;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    if (path == '/session') {
      await sessionPending?.future;
      if (!authenticated) {
        throw const ApiException('UNAUTHENTICATED', 'Zaloguj się.', 401);
      }
      return {
        'user': {'id': 'workspace-owner'},
        'githubAccounts': <Object>[],
      };
    }
    if (path == '/workspace') {
      loads++;
      if (loadError != null) throw loadError!;
      return {
        'definitions': definitions,
        'projects': <Object>[],
        'teams': <Object>[],
      };
    }
    if (path == '/auth/logout') {
      authenticated = false;
      return {};
    }
    if (path.startsWith('/bot-definitions')) {
      final body = Map<String, dynamic>.from(data! as Map);
      writes.add((path: path, method: method, body: body));
      await savePending?.future;
      if (saveError != null) throw saveError!;
      if (method == 'POST') {
        final definition = {'id': 'created-${++created}', ...body};
        definitions.add(definition);
        return {'definition': definition};
      }
      if (method == 'PATCH') {
        final id = Uri.decodeComponent(path.split('/').last);
        final index = definitions.indexWhere(
          (definition) => definition['id'] == id,
        );
        if (index < 0) {
          throw const ApiException(
            'BOT_DEFINITION_NOT_FOUND',
            'Nie znaleziono definicji.',
            404,
          );
        }
        definitions[index] = {'id': id, ...body};
        return {'ok': true};
      }
    }
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<void> forgetSession() async {}
}

Widget _app(_WorkspaceApi api, {String path = '/workspace'}) => ProviderScope(
  overrides: [apiClientProvider.overrideWithValue(api)],
  child: BackendWorkspaceApp(
    initialUri: Uri.parse('https://example.test$path'),
  ),
);

Future<void> _roles(WidgetTester tester, _WorkspaceApi api) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app(api));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Boty i role'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, {String name = 'My bot'}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Nazwa bota'),
    name,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Rola i specjalizacja'),
    'Test engineer',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Opis obowiązków'),
    'Write regression tests.',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Prompt systemowy'),
    'Inspect the task and verify changes with tests.',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Specjalizacje — po jednej w wierszu'),
    'Flutter\nTesting',
  );
}

void main() {
  testWidgets(
    'real workspace never mounts sample data while validating session',
    (tester) async {
      final api = _WorkspaceApi()..sessionPending = Completer<void>();
      await tester.pumpWidget(_app(api));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('AI Workspace'), findsNothing);
      expect(find.text('Tech Lead'), findsNothing);
      expect(api.loads, 0);
      api.sessionPending!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Definicje botów: 0'), findsOneWidget);
      expect(find.text('Projekty: 0'), findsOneWidget);
      expect(find.text('DEMO'), findsNothing);
    },
  );

  testWidgets('empty role workspace supports durable creation and reload', (
    tester,
  ) async {
    final api = _WorkspaceApi();
    await _roles(tester, api);
    expect(
      find.textContaining('Nie masz jeszcze własnych botów'),
      findsOneWidget,
    );
    await tester.tap(find.text('Dodaj własnego bota'));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.text('Zapisz definicję'));
    await tester.pumpAndSettle();

    expect(api.writes.single.method, 'POST');
    expect(api.writes.single.body, {
      'name': 'My bot',
      'role': 'Test engineer',
      'description': 'Write regression tests.',
      'systemPrompt': 'Inspect the task and verify changes with tests.',
      'skills': ['Flutter', 'Testing'],
    });
    expect(api.loads, 2);
    expect(find.widgetWithText(ListTile, 'My bot'), findsOneWidget);
    expect(find.text('Edytuj profil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _roles(tester, api);
    expect(find.widgetWithText(ListTile, 'My bot'), findsOneWidget);
    expect(api.created, 1);
  });

  testWidgets(
    'editing persists the existing definition without creating an instance',
    (tester) async {
      final api = _WorkspaceApi()
        ..definitions.add(_definition('existing-role', 'QA'));
      await _roles(tester, api);
      await tester.tap(find.byTooltip('Edytuj QA'));
      await tester.pumpAndSettle();
      await _fill(tester, name: 'Updated QA');
      await tester.tap(find.text('Zapisz definicję'));
      await tester.pumpAndSettle();

      expect(api.writes.single.path, '/bot-definitions/existing-role');
      expect(api.writes.single.method, 'PATCH');
      expect(api.created, 0);
      expect(find.widgetWithText(ListTile, 'Updated QA'), findsOneWidget);
      expect(
        api.definitions.single['systemPrompt'],
        'Inspect the task and verify changes with tests.',
      );
    },
  );

  testWidgets(
    'cancelled edits do not modify the displayed or stored definition',
    (tester) async {
      final api = _WorkspaceApi()
        ..definitions.add(_definition('existing-role', 'QA'));
      await _roles(tester, api);
      await tester.tap(find.byTooltip('Edytuj QA'));
      await tester.pumpAndSettle();
      await _fill(tester, name: 'Unsaved QA');
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();

      expect(api.writes, isEmpty);
      expect(find.widgetWithText(ListTile, 'QA'), findsOneWidget);
      expect(find.text('Unsaved QA'), findsNothing);
      expect(api.definitions.single['name'], 'QA');
    },
  );

  testWidgets(
    'server rejection keeps the form and supports an explicit retry',
    (tester) async {
      final api = _WorkspaceApi()
        ..saveError = const ApiException(
          'BOT_DEFINITION_NAME_EXISTS',
          'Bot o tej nazwie już istnieje.',
          409,
        );
      await _roles(tester, api);
      await tester.tap(find.text('Dodaj własnego bota'));
      await tester.pumpAndSettle();
      await _fill(tester);
      await tester.tap(find.text('Zapisz definicję'));
      await tester.pumpAndSettle();

      expect(find.text('Bot o tej nazwie już istnieje.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(api.definitions, isEmpty);
      expect(api.loads, 1);
      api.saveError = null;
      await tester.tap(find.text('Zapisz definicję'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.widgetWithText(ListTile, 'My bot'), findsOneWidget);
    },
  );

  testWidgets('creating a role requires a user-authored system prompt', (
    tester,
  ) async {
    final api = _WorkspaceApi();
    await _roles(tester, api);
    await tester.tap(find.text('Dodaj własnego bota'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nazwa bota'),
      'QA',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Rola i specjalizacja'),
      'Testing',
    );
    await tester.tap(find.text('Zapisz definicję'));
    await tester.pumpAndSettle();
    expect(find.text('Uzupełnij to pole.'), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets('catalog specializations are templates until explicitly saved', (
    tester,
  ) async {
    final api = _WorkspaceApi();
    await _roles(tester, api);
    final template = find.widgetWithText(ActionChip, 'Frontend');
    await tester.ensureVisible(template);
    await tester.tap(template);
    await tester.pumpAndSettle();

    expect(api.writes, isEmpty);
    expect(find.widgetWithText(TextFormField, 'Nazwa bota'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Nazwa bota'),
          )
          .controller!
          .text,
      'Frontend',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.widgetWithText(TextFormField, 'Prompt systemowy'),
          )
          .controller!
          .text,
      isEmpty,
    );
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(api.definitions, isEmpty);
  });

  testWidgets(
    'combining definitions creates a new persisted prompt and skill union',
    (tester) async {
      final api = _WorkspaceApi()
        ..definitions.addAll([
          _definition('one', 'Frontend'),
          _definition('two', 'Backend'),
        ]);
      await _roles(tester, api);
      for (final name in ['Frontend', 'Backend']) {
        final checkbox = find.widgetWithText(CheckboxListTile, name);
        await tester.ensureVisible(checkbox);
        await tester.pumpAndSettle();
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Połącz role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Połącz role'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Zapisz definicję'));
      await tester.pumpAndSettle();

      expect(api.writes.single.method, 'POST');
      expect(api.writes.single.body['name'], 'Frontend + Backend');
      expect(
        api.writes.single.body['systemPrompt'],
        'Frontend:\nFrontend prompt\n\nBackend:\nBackend prompt',
      );
      expect(api.writes.single.body['skills'], ['testing']);
      expect(api.definitions, hasLength(3));
    },
  );

  testWidgets('pending save disables double submission and cancellation', (
    tester,
  ) async {
    final api = _WorkspaceApi()..savePending = Completer<void>();
    await _roles(tester, api);
    await tester.tap(find.text('Dodaj własnego bota'));
    await tester.pumpAndSettle();
    await _fill(tester);
    await tester.tap(find.text('Zapisz definicję'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Zapisz definicję'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Anuluj'))
          .onPressed,
      isNull,
    );
    expect(api.writes, hasLength(1));
    api.savePending!.complete();
    await tester.pumpAndSettle();
    expect(api.created, 1);
  });

  testWidgets(
    'workspace error is visible and retry never inserts sample roles',
    (tester) async {
      final api = _WorkspaceApi()
        ..loadError = const ApiException(
          'SERVER_UNAVAILABLE',
          'Brak połączenia z serwerem.',
          503,
        );
      await _roles(tester, api);
      expect(find.text('Brak połączenia z serwerem.'), findsOneWidget);
      expect(find.text('Tech Lead'), findsNothing);
      expect(find.text('Dodaj własnego bota'), findsNothing);
      api.loadError = null;
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Nie masz jeszcze własnych botów'),
        findsOneWidget,
      );
      expect(api.definitions, isEmpty);
    },
  );

  testWidgets(
    'unknown backend URLs show an error rather than the public prototype',
    (tester) async {
      await tester.pumpWidget(
        _app(_WorkspaceApi(), path: '/workspace/unknown'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Nie znaleziono strony panelu.'), findsOneWidget);
      expect(find.text('DEMO'), findsNothing);
      expect(find.text('Tech Lead'), findsNothing);
    },
  );
}
