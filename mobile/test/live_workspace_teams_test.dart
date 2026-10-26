import 'dart:typed_data';

import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/auth/backend_workspace_app.dart';
import 'package:copilot_control_center/src/features/workspace/demo_attachments.dart';
import 'package:copilot_control_center/src/features/workspace/demo_collaboration.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/file_picker_fake.dart';

class _TeamApi extends ApiClient {
  final definitions = [
    for (final (id, name) in [('dev', 'Developer'), ('tester', 'Tester')])
      <String, dynamic>{
        'id': id,
        'name': name,
        'role': '$name role',
        'description': '',
        'systemPrompt': '$name instructions',
        'skills': <String>[],
      },
  ];
  final project = <String, dynamic>{
    'id': 'project',
    'name': 'Shared repository',
    'description': '',
    'repository': 'owner/repository',
    'mainGithubAccountId': 'main',
    'brief': 'Shared specification',
    'repositoryContext': '',
    'files': <Map<String, dynamic>>[],
    'documents': <Object>[],
    'tasks': <Map<String, dynamic>>[],
  };
  final teams = <Map<String, dynamic>>[];
  final writes = <({String path, String method, Map<String, dynamic> body})>[];
  ApiException? saveError;
  ApiException? loadError;
  int _sequence = 0;

  Map<String, dynamic> _member(String teamId, Map<String, dynamic> input) {
    final definition = definitions.firstWhere(
      (role) => role['id'] == input['definitionId'],
    );
    final botId = 'instance-$teamId-${input['definitionId']}';
    return {
      'id': 'membership-$botId',
      'botId': botId,
      'parentId': null,
      'bot': {
        'id': botId,
        'name': definition['name'],
        'definitionId': definition['id'],
        'githubAccountId': input['githubAccountId'],
        'status': 'IDLE',
        'workSchedule': null,
        'stages': <Object>[],
      },
    };
  }

  Map<String, dynamic> seedTeam(String name, {bool onlyDeveloper = false}) {
    final id = 'team-${++_sequence}';
    final team = <String, dynamic>{
      'id': id,
      'name': name,
      'description': '',
      'projectId': project['id'],
      'updatedAt': '2026-10-26T12:00:00.000Z',
      'bots': [
        _member(id, {'definitionId': 'dev', 'githubAccountId': 'main'}),
        if (!onlyDeveloper)
          _member(id, {'definitionId': 'tester', 'githubAccountId': 'other'}),
      ],
      'tasks': <Map<String, dynamic>>[],
    };
    teams.add(team);
    return team;
  }

  Map<String, dynamic> addTask(
    Map<String, dynamic> team,
    Map<String, dynamic> body,
  ) {
    final task = <String, dynamic>{
      'id': 'task-${++_sequence}',
      'status': 'TODO',
      'description': '',
      'priority': 'NORMAL',
      ...body,
      'teamId': team['id'],
    };
    (team['tasks'] as List).add(task);
    (project['tasks'] as List).add(task);
    return task;
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    if (path == '/session') {
      return {
        'user': {'id': 'owner'},
        'githubAccounts': [
          {
            'id': 'main',
            'login': 'owner',
            'status': 'ACTIVE',
            'scopes': ['repo'],
          },
          {
            'id': 'other',
            'login': 'secondary',
            'status': 'ACTIVE',
            'scopes': ['repo'],
          },
        ],
      };
    }
    if (path == '/workspace') {
      if (loadError != null) throw loadError!;
      return {
        'definitions': definitions,
        'projects': [project],
        'teams': teams,
      };
    }
    final body = data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(data as Map);
    writes.add((path: path, method: method, body: body));
    if (saveError != null) throw saveError!;
    if (path.startsWith('/workspace/bots/') &&
        path.endsWith('/schedule') &&
        method == 'POST') {
      final botId = path.split('/')[3];
      final member = teams
          .expand((team) => (team['bots'] as List).cast<Map<String, dynamic>>())
          .firstWhere((member) => member['botId'] == botId);
      final schedule = {'id': 'schedule-$botId', 'botId': botId, ...body};
      (member['bot'] as Map)['workSchedule'] = schedule;
      return {'schedule': schedule};
    }
    if (path == '/workspace/teams' && method == 'POST') {
      final team = seedTeam(body['name'] as String);
      team['description'] = body['description'];
      team['bots'] = [
        for (final input in body['members'] as List)
          _member(
            team['id'] as String,
            Map<String, dynamic>.from(input as Map),
          ),
      ];
      for (final input in body['tasks'] as List) {
        final task = Map<String, dynamic>.from(input as Map);
        final member = (team['bots'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (member) =>
                  (member['bot'] as Map)['definitionId'] ==
                  task['definitionId'],
            );
        task.remove('definitionId');
        addTask(team, {...task, 'botId': member['botId']});
      }
      return {'team': team};
    }
    if (path.startsWith('/workspace/teams/')) {
      final parts = path.split('/');
      final team = teams.firstWhere((team) => team['id'] == parts[3]);
      if (parts.last == 'tasks' && method == 'POST') {
        return {'task': addTask(team, body)};
      }
      if (parts.last == 'hierarchy' && method == 'PATCH') {
        if (body['updatedAt'] != team['updatedAt']) {
          throw const ApiException(
            'TEAM_CHANGED',
            'Team changed; reload hierarchy.',
          );
        }
        for (final input in body['members'] as List) {
          final update = Map<String, dynamic>.from(input as Map);
          (team['bots'] as List).cast<Map<String, dynamic>>().firstWhere(
            (member) => member['id'] == update['id'],
          )['parentId'] = update['parentId'];
        }
        team['updatedAt'] = '2026-10-26T12:00:01.000Z';
        return {'ok': true};
      }
      if (parts.last == 'members' && method == 'POST') {
        final member = _member(team['id'] as String, body);
        (team['bots'] as List).add(member);
        team['updatedAt'] = '2026-10-26T12:00:02.000Z';
        return {'member': member};
      }
      if (parts[4] == 'members' && method == 'DELETE') {
        final member = (team['bots'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((member) => member['id'] == parts.last);
        if ((team['tasks'] as List).any(
          (task) => (task as Map)['botId'] == member['botId'],
        )) {
          throw const ApiException(
            'BOT_HAS_TASKS',
            'Reassign tasks before removing this bot.',
          );
        }
        (team['bots'] as List).remove(member);
        team['updatedAt'] = '2026-10-26T12:00:03.000Z';
        return {};
      }
    }
    if (path.startsWith('/workspace/tasks/') || path.startsWith('/tasks/')) {
      final task = (project['tasks'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((task) => task['id'] == path.split('/').last);
      if (method == 'DELETE') {
        (project['tasks'] as List).remove(task);
        for (final team in teams) {
          (team['tasks'] as List).remove(task);
        }
        return {};
      }
      task.addAll(body);
      return path.startsWith('/tasks/') ? {'task': task} : {'ok': true};
    }
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<Map<String, dynamic>> uploadWorkspaceFile({
    required String collection,
    required String ownerId,
    required String filename,
    required Uint8List bytes,
  }) async {
    expect(collection, 'projects');
    expect(ownerId, 'project');
    final file = {
      'id': 'uploaded-${++_sequence}',
      'filename': filename,
      'sizeBytes': bytes.length,
    };
    (project['files'] as List).add(file);
    return {'file': file};
  }
}

Future<void> _open(WidgetTester tester, _TeamApi api, {String? team}) async {
  tester.view.physicalSize = const Size(1440, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: BackendWorkspaceApp(
        initialUri: Uri.parse('https://example.test/workspace'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Zespoły AI'));
  await tester.pumpAndSettle();
  if (team != null) await _tap(tester, team);
}

Future<void> _tap(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String label, String value) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, value);
}

Future<void> _select(WidgetTester tester, String label, String value) async {
  final field = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
  );
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.tap(field);
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _plan(WidgetTester tester, {String name = 'Frontend'}) async {
  await _tap(tester, 'Utwórz zespół');
  await _fill(tester, 'Nazwa zespołu', name);
  await _select(
    tester,
    'Wspólny projekt',
    'Shared repository · owner/repository',
  );
  await _tap(tester, 'Boty');
  await _tap(tester, 'Developer');
  await _tap(tester, 'Tester');
  await _tap(tester, 'GitHub');
  await _select(tester, 'Developer — konto GitHub', '@owner');
  await _select(tester, 'Tester — konto GitHub', '@secondary');
}

void main() {
  late TestFilePicker picker;
  setUp(() {
    final previous = FilePickerPlatform.instance;
    picker = TestFilePicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
  });

  testWidgets(
    'team wizard persists per-bot accounts and priority without starting SDK',
    (tester) async {
      final api = _TeamApi();
      await _open(tester, api);
      await _plan(tester);
      await _tap(tester, 'Zadanie');
      await _tap(tester, 'Developer');
      await _tap(tester, 'Dodaj task');
      await _fill(tester, 'Tytuł taska', 'Build navigation');
      await _select(tester, 'Priorytet', 'Pilny');
      await _tap(tester, 'Zapisz task');
      expect(api.writes, isEmpty);
      await _tap(tester, 'Zapis');
      await _tap(tester, 'Zapisz zespół');
      expect(api.writes.single.path, '/workspace/teams');
      expect(api.writes.single.body, {
        'name': 'Frontend',
        'description': '',
        'projectId': 'project',
        'members': [
          {'definitionId': 'dev', 'githubAccountId': 'main'},
          {'definitionId': 'tester', 'githubAccountId': 'other'},
        ],
        'tasks': [
          {
            'definitionId': 'dev',
            'title': 'Build navigation',
            'description': '',
            'priority': 'URGENT',
          },
        ],
      });
      expect(find.text('Build navigation'), findsOneWidget);
      await _tap(tester, 'Boty i GitHub');
      expect(find.textContaining('GitHub: @owner'), findsOneWidget);
      expect(find.textContaining('GitHub: @secondary'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await _open(tester, api, team: 'Frontend');
      expect(find.text('Build navigation'), findsOneWidget);
    },
  );

  testWidgets(
    'teams sharing a project retain independent bot instances and task filters',
    (tester) async {
      final api = _TeamApi();
      final first = api.seedTeam('Frontend');
      final second = api.seedTeam('Backend');
      api.addTask(first, {
        'title': 'Frontend only',
        'botId': (first['bots'] as List).first['botId'],
      });
      api.addTask(second, {
        'title': 'Backend only',
        'botId': (second['bots'] as List).first['botId'],
      });
      await _open(tester, api, team: 'Frontend');
      expect(find.text('Frontend only'), findsOneWidget);
      expect(find.text('Backend only'), findsNothing);
      await _tap(tester, 'Tester');
      expect(find.text('Frontend only'), findsNothing);
      await _tap(tester, 'Wszystkie boty');
      expect(find.text('Frontend only'), findsOneWidget);
      await _tap(tester, 'Lista zespołów');
      await _tap(tester, 'Backend');
      expect(find.text('Frontend only'), findsNothing);
      expect(find.text('Backend only'), findsOneWidget);
      expect(
        (first['bots'] as List).first['botId'],
        isNot((second['bots'] as List).first['botId']),
      );
    },
  );

  testWidgets(
    'wizard rejects missing account and retains plan after server failure',
    (tester) async {
      final api = _TeamApi();
      await _open(tester, api);
      await _tap(tester, 'Utwórz zespół');
      await _fill(tester, 'Nazwa zespołu', 'Missing account');
      await _select(
        tester,
        'Wspólny projekt',
        'Shared repository · owner/repository',
      );
      await _tap(tester, 'Boty');
      await _tap(tester, 'Developer');
      await _tap(tester, 'Zapis');
      await _tap(tester, 'Zapisz zespół');
      expect(
        find.text('Wybierz aktywne konto GitHub dla każdego bota.'),
        findsOneWidget,
      );
      expect(api.writes, isEmpty);
      await _select(tester, 'Developer — konto GitHub', '@owner');
      api.saveError = const ApiException(
        'GITHUB_REPOSITORY_READ_ONLY',
        'Repository write access denied.',
      );
      await _tap(tester, 'Zapis');
      await _tap(tester, 'Zapisz zespół');
      expect(find.text('Repository write access denied.'), findsOneWidget);
      expect(api.teams, isEmpty);
      api.saveError = null;
      await _tap(tester, 'Zapisz zespół');
      expect(api.teams.single['name'], 'Missing account');
    },
  );

  testWidgets(
    'PDF drafts survive wizard steps and refresh errors without silently losing attachments',
    (tester) async {
      final api = _TeamApi();
      await _open(tester, api);
      await _plan(tester);
      await _tap(tester, 'PDF');
      picker.selection = [TestPickedFile('specification.pdf')];
      await _tap(tester, 'Dodaj pliki');
      await _tap(tester, 'Zadanie');
      await _tap(tester, 'Zapis');
      await _tap(tester, 'Zapisz zespół');
      expect(api.writes, isEmpty);
      expect(
        find.text(
          'Wyślij wybrane pliki lub usuń je z listy przed zapisaniem zespołu.',
        ),
        findsOneWidget,
      );
      expect(find.text('specification.pdf (1 KB)'), findsOneWidget);
      api.loadError = const ApiException(
        'SERVER_UNAVAILABLE',
        'Refresh unavailable.',
      );
      await _tap(tester, 'Prześlij wybrane pliki');
      expect(find.text('Nie udało się odświeżyć danych'), findsOneWidget);
      expect(
        tester.widget<DemoAttachments>(find.byType(DemoAttachments)).files,
        isEmpty,
      );
      await _tap(tester, 'Projekt');
      expect(find.text('Frontend'), findsOneWidget);
      api.loadError = null;
      await _tap(tester, 'Ponów odświeżanie');
      await _tap(tester, 'PDF');
      expect(find.text('specification.pdf (1 KB)'), findsOneWidget);
      await _tap(tester, 'Zapis');
      await _tap(tester, 'Zapisz zespół');
      expect(api.teams.single['name'], 'Frontend');
    },
  );

  testWidgets(
    'task creation, reassignment, priority and status persist; rejected status rolls back',
    (tester) async {
      final api = _TeamApi()..seedTeam('Frontend');
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Developer');
      await _tap(tester, 'Dodaj task');
      await _fill(tester, 'Tytuł taska', 'Verify deployment');
      await _tap(tester, 'Zapisz task');
      expect(find.text('Verify deployment'), findsOneWidget);
      await _tap(tester, 'Edytuj task');
      await _select(tester, 'Bot odpowiedzialny', 'Tester');
      await _select(tester, 'Priorytet', 'Wysoki');
      await _tap(tester, 'Zapisz task');
      expect(find.text('Verify deployment'), findsNothing);
      await _tap(tester, 'Tester');
      expect(find.text('Verify deployment'), findsOneWidget);
      expect(find.text('Tester · priorytet: Wysoki'), findsOneWidget);
      api.saveError = const ApiException(
        'TASK_DEPENDENCIES_UNMET',
        'Dependencies are incomplete.',
      );
      await _select(tester, 'Status taska', 'Gotowe');
      expect(find.text('Dependencies are incomplete.'), findsOneWidget);
      final status = tester.widget<DropdownButtonFormField<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Status taska',
        ),
      );
      expect(status.initialValue, 'TODO');
      final statusState = tester.state<FormFieldState<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is DropdownButtonFormField<String> &&
              widget.decoration.labelText == 'Status taska',
        ),
      );
      expect(statusState.value, 'TODO');
      api.saveError = null;
      await _select(tester, 'Status taska', 'Gotowe');
      expect((api.project['tasks'] as List).single['status'], 'COMPLETED');
      await _tap(tester, 'Usuń task');
      await _tap(tester, 'Anuluj');
      expect(find.text('Verify deployment'), findsOneWidget);
      await _tap(tester, 'Usuń task');
      await _tap(tester, 'Usuń');
      expect(find.text('Verify deployment'), findsNothing);
    },
  );

  testWidgets(
    'task save failure keeps entered text and does not fabricate a saved task',
    (tester) async {
      final api = _TeamApi()..seedTeam('Frontend');
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Dodaj task');
      await _fill(tester, 'Tytuł taska', 'Unpublished task');
      await _select(tester, 'Bot odpowiedzialny', 'Developer');
      api.saveError = const ApiException(
        'SERVER_UNAVAILABLE',
        'Save unavailable.',
      );
      await _tap(tester, 'Zapisz task');
      expect(find.text('Save unavailable.'), findsOneWidget);
      expect(find.text('Unpublished task'), findsOneWidget);
      expect(api.project['tasks'], isEmpty);
      await _tap(tester, 'Anuluj');
      expect(find.text('Unpublished task'), findsNothing);
    },
  );

  testWidgets(
    'hierarchy uses membership ids, prevents cycles and saves full versioned snapshot',
    (tester) async {
      final api = _TeamApi()..seedTeam('Frontend');
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Współpraca');
      await _tap(tester, 'Developer');
      await _select(tester, 'Raportuje do', 'Tester');
      await _tap(tester, 'Zapisz relację');
      expect(api.writes, isEmpty);
      await _tap(tester, 'Tester');
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('Developer')),
        findsNothing,
      );
      await _tap(tester, 'Anuluj');
      await _tap(tester, 'Zadania');
      await _tap(tester, 'Współpraca');
      final graph = tester.widget<DemoCollaboration>(
        find.byType(DemoCollaboration),
      );
      expect(graph.parents, {
        'membership-instance-team-1-dev': 'membership-instance-team-1-tester',
      });
      await _tap(tester, 'Zapisz hierarchię');
      expect(api.writes.single.body, {
        'updatedAt': '2026-10-26T12:00:00.000Z',
        'members': [
          {
            'id': 'membership-instance-team-1-dev',
            'parentId': 'membership-instance-team-1-tester',
          },
          {'id': 'membership-instance-team-1-tester', 'parentId': null},
        ],
      });
      await tester.pumpWidget(const SizedBox());
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Współpraca');
      expect(
        tester
            .widget<DemoCollaboration>(find.byType(DemoCollaboration))
            .parents,
        graph.parents,
      );
    },
  );

  testWidgets(
    'hierarchy conflict preserves draft and requires explicit reload',
    (tester) async {
      final api = _TeamApi()..seedTeam('Frontend');
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Współpraca');
      await _tap(tester, 'Developer');
      await _select(tester, 'Raportuje do', 'Tester');
      await _tap(tester, 'Zapisz relację');
      api.teams.single['updatedAt'] = '2026-10-26T12:00:03.000Z';
      await _tap(tester, 'Zapisz hierarchię');
      expect(find.text('Team changed; reload hierarchy.'), findsOneWidget);
      expect(
        tester
            .widget<DemoCollaboration>(find.byType(DemoCollaboration))
            .parents,
        isNotEmpty,
      );
      await _tap(tester, 'Wczytaj aktualną hierarchię');
      expect(
        tester
            .widget<DemoCollaboration>(find.byType(DemoCollaboration))
            .parents,
        isEmpty,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Zapisz hierarchię'),
            )
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'calendar persists ISO weekdays and IANA timezone for the selected instance only',
    (tester) async {
      final api = _TeamApi()
        ..seedTeam('Frontend')
        ..seedTeam('Backend');
      await _open(tester, api);
      await tester.tap(find.widgetWithText(ListTile, 'Kalendarz'));
      await tester.pumpAndSettle();
      await _select(tester, 'Bot', 'Backend · Tester');
      final timezone = find.widgetWithText(TextField, 'Strefa czasowa IANA');
      await tester.enterText(timezone, 'UTC');
      await _tap(tester, 'Niedziela');
      await _tap(tester, 'Harmonogram włączony');
      await _tap(tester, 'Zapisz harmonogram');
      expect(
        api.writes.single.path,
        '/workspace/bots/instance-team-2-tester/schedule',
      );
      expect(api.writes.single.body, {
        'timezone': 'UTC',
        'enabled': true,
        'days': [1, 2, 3, 4, 5, 7],
        'startTime': '09:00',
        'endTime': '17:00',
      });
      expect(
        find.text('Backend · Tester · 09:00–17:00 · UTC'),
        findsNWidgets(6),
      );
      expect(
        ((api.teams.first['bots'] as List).first['bot'] as Map)['workSchedule'],
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await _open(tester, api);
      await tester.tap(find.widgetWithText(ListTile, 'Kalendarz'));
      await tester.pumpAndSettle();
      await _select(tester, 'Bot', 'Backend · Tester');
      expect(find.text('UTC'), findsOneWidget);
      expect(
        find.text('Backend · Tester · 09:00–17:00 · UTC'),
        findsNWidgets(6),
      );
    },
  );

  testWidgets(
    'team membership selects real account and cannot detach a bot with tasks',
    (tester) async {
      final api = _TeamApi();
      final team = api.seedTeam('Frontend', onlyDeveloper: true);
      api.addTask(team, {
        'title': 'Assigned task',
        'botId': (team['bots'] as List).first['botId'],
      });
      await _open(tester, api, team: 'Frontend');
      await _tap(tester, 'Boty i GitHub');
      await _tap(tester, 'Dodaj bota do zespołu');
      await _select(tester, 'Definicja bota', 'Tester');
      await _select(tester, 'Konto GitHub instancji', '@secondary');
      await _tap(tester, 'Dodaj instancję');
      expect(api.writes.single.body, {
        'definitionId': 'tester',
        'githubAccountId': 'other',
      });
      expect(find.textContaining('GitHub: @secondary'), findsOneWidget);
      await tester.tap(find.byTooltip('Odłącz Developer'));
      await tester.pumpAndSettle();
      await _tap(tester, 'Odłącz bota');
      expect(
        find.text('Reassign tasks before removing this bot.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Odłącz Developer'), findsOneWidget);
      await tester.tap(find.byTooltip('Odłącz Tester'));
      await tester.pumpAndSettle();
      await _tap(tester, 'Odłącz bota');
      expect(find.byTooltip('Odłącz Tester'), findsNothing);
      expect((team['bots'] as List), hasLength(1));
    },
  );
}
