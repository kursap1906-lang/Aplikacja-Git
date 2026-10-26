import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_agent_dialog.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_dashboard.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_github_page.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeliveryApi extends ApiClient {
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    calls.add('$method $path');
    if (path == '/workspace/tasks/task/agent-stage') {
      return method == 'GET'
          ? {'stage': null, 'execution': 'GITHUB_HOSTED'}
          : {
              'stage': {'id': 'stage', 'status': 'PENDING'},
              'execution': 'GITHUB_HOSTED',
            };
    }
    if (path == '/stages/stage/start') {
      return {
        'stage': {'id': 'stage', 'status': 'RUNNING'},
        'task': {'state': 'queued', 'url': 'https://github.com/fixture/repo'},
      };
    }
    if (path == '/workspace/settings') {
      return {
        'integrations': [
          {
            'id': 'github',
            'name': 'GitHub',
            'category': 'AI i GitHub',
            'description': 'Repozytoria i PR',
            'supported': true,
            'status': 'CONFIGURED',
            'configuration': 'OAuth',
          },
          {
            'id': 'blender',
            'name': 'Blender',
            'category': 'CAD i grafika',
            'description': 'Grafika 3D',
            'supported': false,
            'status': 'UNAVAILABLE',
            'configuration': 'Brak adaptera',
          },
        ],
        'security': <String, dynamic>{},
        'automation': <String, dynamic>{},
      };
    }
    if (path.startsWith('/github/accounts/account/repositories')) {
      return {
        'repositories': [
          {
            'id': 'repo',
            'fullName': 'fixture/repo',
            'name': 'repo',
            'owner': 'fixture',
            'defaultBranch': 'main',
            'isPrivate': true,
            'canPush': true,
          },
        ],
        'nextPage': null,
      };
    }
    if (path.startsWith('/workspace/github/pulls?')) {
      return {
        'pulls': [
          {
            'number': 7,
            'title': 'Tested change',
            'state': 'draft',
            'url': 'https://github.com/fixture/repo/pull/7',
            'head': 'feature',
            'base': 'main',
            'author': 'fixture',
          },
        ],
        'nextPage': null,
      };
    }
    throw StateError('Unexpected request: $method $path');
  }
}

final _accounts = parseWorkspaceAccounts({
  'githubAccounts': [
    {
      'id': 'account',
      'login': 'fixture',
      'status': 'ACTIVE',
      'scopes': ['repo'],
    },
  ],
});

Future<void> _mount(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('metric labels remain readable in the deployed dark theme', (
    tester,
  ) async {
    final theme = ThemeData.dark();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: WorkspaceMetricCard(
            title: 'Metric label',
            value: '5',
            subtitle: 'Metric detail',
            icon: Icons.smart_toy_outlined,
          ),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('Metric label')).style!.color,
      theme.colorScheme.onSurfaceVariant,
    );
    expect(
      tester.widget<Text>(find.text('Metric detail')).style!.color,
      theme.colorScheme.onSurfaceVariant,
    );
  });

  testWidgets('dashboard restores metric tiles without inventing balances', (
    tester,
  ) async {
    final data = WorkspaceData.fromJson({
      'definitions': [],
      'projects': [],
      'teams': [],
    });
    var openedCosts = false;
    await _mount(
      tester,
      WorkspaceDashboard(
        data: data,
        onReload: () {},
        onCosts: () => openedCosts = true,
        onCreateTeam: () {},
        onTeam: (_) {},
      ),
    );
    for (final title in [
      'Wszystkie boty',
      'Otwarte zadania',
      'Zakończone zadania',
      'Koszt abonamentów / mies.',
      'Pozostałe kredyty AI',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('Pozostałe kredyty AI'));
    expect(openedCosts, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'GitHub tab selects a real account and repository before loading PRs',
    (tester) async {
      final api = _DeliveryApi();
      await _mount(
        tester,
        WorkspaceGitHubPage(api: api, accounts: _accounts, projects: const []),
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('@fixture').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('fixture/repo').last);
      await tester.pumpAndSettle();
      expect(find.text('#7 · Tested change'), findsOneWidget);
      expect(api.calls.any((call) => call.startsWith('POST ')), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings restores integration catalog and unsupported adapter details',
    (tester) async {
      await _mount(
        tester,
        WorkspaceSettingsPage(
          api: _DeliveryApi(),
          accounts: _accounts,
          onCalendar: () {},
        ),
      );
      expect(find.text('GitHub'), findsOneWidget);
      expect(find.text('Blender'), findsOneWidget);
      await tester.tap(find.text('Blender'));
      await tester.pumpAndSettle();
      expect(find.text('Brak adaptera'), findsOneWidget);
      expect(find.text('Konta GitHub'), findsOneWidget);
      expect(find.text('Automatyzacje'), findsOneWidget);
      expect(find.text('Bezpieczeństwo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('agent dialog never starts work until explicit GitHub launch', (
    tester,
  ) async {
    final api = _DeliveryApi();
    final task = parseWorkspaceTask({
      'id': 'task',
      'title': 'Build app',
      'description': '',
      'status': 'TODO',
      'priority': 'NORMAL',
      'botId': 'bot',
      'teamId': 'team',
    });
    await _mount(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showWorkspaceAgent(
            context,
            api: api,
            task: task,
            onChanged: () {},
          ),
          child: const Text('Agent'),
        ),
      ),
    );
    await tester.tap(find.text('Agent'));
    await tester.pumpAndSettle();
    expect(api.calls, ['GET /workspace/tasks/task/agent-stage']);
    await tester.tap(find.text('Uruchom na GitHub'));
    await tester.pumpAndSettle();
    expect(api.calls, [
      'GET /workspace/tasks/task/agent-stage',
      'POST /workspace/tasks/task/agent-stage',
      'POST /stages/stage/start',
    ]);
    expect(find.text('GitHub: queued'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
