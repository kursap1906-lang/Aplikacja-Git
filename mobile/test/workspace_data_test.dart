import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _snapshot() => {
  'definitions': [
    {
      'id': 'definition',
      'name': 'Developer',
      'role': 'Implementation',
      'description': '',
      'systemPrompt': 'Write tested code.',
      'skills': ['TypeScript'],
    },
  ],
  'projects': [
    {
      'id': 'project',
      'name': 'Shared project',
      'description': '',
      'repository': 'fixture/repository',
      'brief': 'Specification',
      'repositoryContext': 'Architecture',
      'files': [
        {'id': 'file', 'filename': 'spec.bin', 'sizeBytes': 42},
      ],
      'documents': [],
      'tasks': [],
    },
  ],
  'teams': [
    {
      'id': 'team',
      'name': 'Frontend',
      'description': '',
      'projectId': 'project',
      'updatedAt': '2026-10-26T12:00:00.000Z',
      'bots': [
        {
          'id': 'membership',
          'parentId': null,
          'botId': 'instance',
          'bot': {
            'id': 'instance',
            'definitionId': 'definition',
            'name': 'Developer',
            'status': 'IDLE',
            'githubAccountId': 'account',
            'workSchedule': null,
            'stages': [],
          },
        },
      ],
      'tasks': [
        {
          'id': 'task',
          'title': 'Implement UI',
          'description': '',
          'botId': 'instance',
          'status': 'TODO',
          'priority': 'HIGH',
        },
      ],
    },
  ],
};

class _RepositoryApi extends ApiClient {
  Map<String, dynamic> response = {'repositories': []};

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async => response;
}

void main() {
  final invalidResponse = throwsA(
    isA<ApiException>().having(
      (error) => error.code,
      'code',
      'INVALID_WORKSPACE_RESPONSE',
    ),
  );

  test(
    'parses server role definitions independently of team execution instances',
    () {
      final workspace = WorkspaceData.fromJson(_snapshot());
      expect(workspace.roles.single.id, 'definition');
      expect(workspace.teams.single.members.single.definitionId, 'definition');
      expect(workspace.teams.single.members.single.botId, 'instance');
      expect(workspace.teams.single.projectId, workspace.projects.single.id);
      expect(workspace.teams.single.tasks.single.botId, 'instance');
      expect(workspace.teams.single.tasks.single.priority, 'HIGH');
      expect(workspace.projects.single.files.single.sizeBytes, 42);
    },
  );

  test(
    'empty workspace stays empty rather than receiving demonstration data',
    () {
      final workspace = WorkspaceData.fromJson({
        'definitions': [],
        'projects': [],
        'teams': [],
      });
      expect(workspace.roles, isEmpty);
      expect(workspace.projects, isEmpty);
      expect(workspace.teams, isEmpty);
    },
  );

  test(
    'missing and malformed collections are errors, not empty workspaces',
    () {
      for (final response in [
        <String, dynamic>{},
        <String, dynamic>{
          'definitions': 'invalid',
          'projects': [],
          'teams': [],
        },
        <String, dynamic>{
          'definitions': [42],
          'projects': [],
          'teams': [],
        },
        <String, dynamic>{
          'definitions': [],
          'projects': [],
          'teams': [{}],
        },
      ]) {
        expect(() => WorkspaceData.fromJson(response), invalidResponse);
      }
    },
  );

  test('unknown task priorities cannot be silently mapped to normal', () {
    final snapshot = _snapshot();
    snapshot['teams'][0]['tasks'][0]['priority'] = 'UNKNOWN';
    expect(() => WorkspaceData.fromJson(snapshot), invalidResponse);
  });

  test(
    'mismatched membership IDs cannot display another bot as the assignee',
    () {
      final snapshot = _snapshot();
      snapshot['teams'][0]['bots'][0]['botId'] = 'another-instance';
      expect(() => WorkspaceData.fromJson(snapshot), invalidResponse);
    },
  );

  test('connected account list preserves inactive accounts without fabricating entries', () {
    final accounts = parseWorkspaceAccounts({
      'githubAccounts': [
        {
          'id': 'account',
          'login': 'fixture',
          'status': 'REAUTH_REQUIRED',
          'scopes': ['repo'],
        },
      ],
    });
    expect(accounts.single.login, 'fixture');
    expect(accounts.single.active, isFalse);
    expect(accounts.single.scopes, ['repo']);
    expect(
      () => parseWorkspaceAccounts({
        'githubAccounts': [
          {'id': 'account', 'login': 'fixture', 'status': 'ACTIVE'},
        ],
      }),
      invalidResponse,
    );
    expect(() => parseWorkspaceAccounts({}), invalidResponse);
  });

  test(
    'repository response is validated rather than silently filtered',
    () async {
      final api = _RepositoryApi()
        ..response = {
          'nextPage': 2,
          'repositories': [
            {'id': '123', 'fullName': 'fixture/repository', 'canPush': true},
          ],
        };
      final page = await loadWorkspaceRepositoryPage(api, 'account');
      final repositories = page.repositories;
      expect(repositories.single.fullName, 'fixture/repository');
      expect(repositories.single.canPush, isTrue);
      expect(page.nextPage, 2);
      api.response = {
        'nextPage': null,
        'repositories': [{}],
      };
      await expectLater(
        loadWorkspaceRepositoryPage(api, 'account'),
        invalidResponse,
      );
      api.response = {};
      await expectLater(
        loadWorkspaceRepositoryPage(api, 'account'),
        invalidResponse,
      );
    },
  );

  test(
    'repository pagination rejects absent or nonsequential continuation',
    () async {
      final api = _RepositoryApi();
      for (final next in [0, 1, 3, '2']) {
        api.response = {'repositories': <Object>[], 'nextPage': next};
        await expectLater(
          loadWorkspaceRepositoryPage(api, 'account'),
          invalidResponse,
        );
      }
      api.response = {'repositories': <Object>[], 'nextPage': null};
      expect(
        (await loadWorkspaceRepositoryPage(api, 'account')).nextPage,
        isNull,
      );
    },
  );

  test('schedule response requires unique ISO days and a valid same-day time range', () {
    final valid = <String, dynamic>{
      'timezone': 'Europe/Warsaw',
      'enabled': true,
      'days': [1, 7],
      'startTime': '09:00',
      'endTime': '17:00',
    };
    expect(parseWorkspaceSchedule(valid).days, [1, 7]);
    for (final days in [
      <int>[],
      [0],
      [8],
      [1, 1],
    ]) {
      expect(
        () => parseWorkspaceSchedule({...valid, 'days': days}),
        invalidResponse,
      );
    }
    for (final change in [
      {'startTime': '9:00'},
      {'endTime': '25:00'},
      {'endTime': '09:00'},
      {'startTime': '18:00'},
      {'timezone': ''},
    ]) {
      expect(
        () => parseWorkspaceSchedule({...valid, ...change}),
        invalidResponse,
      );
    }
  });
}
