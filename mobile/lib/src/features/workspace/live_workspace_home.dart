import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../auth/authenticated_workspace_gate.dart';
import '../schedule/demo_schedule_page.dart';
import 'workspace_data.dart';
import 'workspace_roles_page.dart';
import 'workspace_projects_page.dart';
import 'workspace_shell.dart';
import 'workspace_teams_page.dart';
import 'workspace_costs_page.dart';
import 'workspace_dashboard.dart';
import 'workspace_github_page.dart';
import 'workspace_settings_page.dart';

class LiveWorkspaceRoot extends StatelessWidget {
  const LiveWorkspaceRoot({super.key});

  @override
  Widget build(BuildContext context) => AuthenticatedWorkspaceGate(
    builder: (context, session, logout) =>
        LiveWorkspaceHome(onLogout: logout, session: session),
  );
}

class LiveWorkspaceHome extends ConsumerStatefulWidget {
  const LiveWorkspaceHome({
    required this.onLogout,
    required this.session,
    super.key,
  });

  final Future<void> Function() onLogout;
  final Map<String, dynamic> session;

  @override
  ConsumerState<LiveWorkspaceHome> createState() => _LiveWorkspaceHomeState();
}

class _LiveWorkspaceHomeState extends ConsumerState<LiveWorkspaceHome> {
  int _page = 0;
  bool _loggingOut = false;
  String? _teamId;

  void _reload() {
    if (mounted) ref.invalidate(workspaceDataProvider);
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await widget.onLogout();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Widget _withAccounts(Widget Function(List<WorkspaceAccount>) builder) {
    try {
      return builder(parseWorkspaceAccounts(widget.session));
    } on ApiException catch (error) {
      return WorkspacePanel(
        title: 'Nie udało się wczytać kont GitHub',
        child: Text(error.toString()),
      );
    }
  }

  Widget _projects(WorkspaceData data) => _withAccounts(
    (accounts) => WorkspaceProjectsPage(
      projects: data.projects,
      teams: data.teams,
      accounts: accounts,
      api: ref.read(apiClientProvider),
      onChanged: _reload,
      onConnectAccounts: () => context.go('/connect'),
    ),
  );

  Widget _dashboard(WorkspaceData data) => WorkspaceDashboard(
    data: data,
    onReload: _reload,
    onCosts: () => setState(() => _page = 5),
    onCreateTeam: () => setState(() {
      _teamId = null;
      _page = 1;
    }),
    onTeam: (id) => setState(() {
      _teamId = id;
      _page = 1;
    }),
  );

  Widget _calendar(WorkspaceData data) {
    final bots = {
      for (final team in data.teams)
        for (final member in team.members)
          member.botId: (
            id: member.botId,
            name: '${team.name} · ${member.name}',
            schedule: member.schedule,
          ),
    };
    return WorkspacePanel(
      title: 'Kalendarz instancji botów',
      child: BotSchedulePage(
        agents: [for (final bot in bots.values) (id: bot.id, name: bot.name)],
        schedules: {for (final bot in bots.values) bot.id: ?bot.schedule},
        onSave: (id, schedule) async {
          final response = await ref
              .read(apiClientProvider)
              .request(
                '/workspace/bots/${Uri.encodeComponent(id)}/schedule',
                method: 'POST',
                data: {
                  'timezone': schedule.timezone,
                  'enabled': schedule.enabled,
                  'days': schedule.days,
                  'startTime': schedule.startTime,
                  'endTime': schedule.endTime,
                },
              );
          final raw = response['schedule'];
          if (raw is! Map<String, dynamic> || raw['botId'] != id) {
            throw const ApiException(
              'INVALID_WORKSPACE_RESPONSE',
              'Serwer nie potwierdził harmonogramu tej instancji.',
            );
          }
          final saved = parseWorkspaceSchedule(raw);
          if (saved.timezone != schedule.timezone ||
              saved.enabled != schedule.enabled ||
              !listEquals(saved.days, schedule.days) ||
              saved.startTime != schedule.startTime ||
              saved.endTime != schedule.endTime) {
            throw const ApiException(
              'INVALID_WORKSPACE_RESPONSE',
              'Serwer zwrócił inny harmonogram niż zapisany.',
            );
          }
          _reload();
        },
      ),
    );
  }

  Widget _pageBody(WorkspaceData data) => switch (_page) {
    0 => _dashboard(data),
    1 => _withAccounts(
      (accounts) => WorkspaceTeamsPage(
        data: data,
        accounts: accounts,
        api: ref.read(apiClientProvider),
        onChanged: _reload,
        initialTeamId: _teamId,
      ),
    ),
    2 => WorkspaceRolesPage(
      roles: data.roles,
      api: ref.read(apiClientProvider),
      onChanged: _reload,
    ),
    3 => _projects(data),
    6 => _calendar(data),
    7 => _withAccounts(
      (accounts) => WorkspaceSettingsPage(
        api: ref.read(apiClientProvider),
        accounts: accounts,
        onCalendar: () => setState(() => _page = 6),
      ),
    ),
    4 => _withAccounts(
      (accounts) => WorkspaceGitHubPage(
        api: ref.read(apiClientProvider),
        accounts: accounts,
        projects: data.projects,
        teams: data.teams,
      ),
    ),
    5 => WorkspaceCostsPage(api: ref.read(apiClientProvider)),
    _ => throw StateError('Unknown workspace page: $_page'),
  };

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(workspaceDataProvider);
    return WorkspaceShell(
      page: _page,
      title: workspaceNavigation[_page].$1,
      banner:
          'Boty uruchamiasz ręcznie w repozytorium GitHub (Agents). '
          'Panel nie wykonuje zadań lokalnie. Zmiany wymagają przeglądu; brak automatycznego merge.',
      status: 'API · GitHub Agents',
      onNavigate: (page) => setState(() => _page = page),
      onLogout: _logout,
      loggingOut: _loggingOut,
      onNotifications: () => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Powiadomienia SDK'),
          content: const Text(
            'Usługa sesji botów nie jest jeszcze podłączona do tego panelu. Nie ma demonstracyjnych powiadomień.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zamknij'),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (workspace.hasError && workspace.hasValue)
            WorkspacePanel(
              title: 'Nie udało się odświeżyć danych',
              trailing: OutlinedButton(
                onPressed: _reload,
                child: const Text('Ponów odświeżanie'),
              ),
              child: Text(
                'Zachowano ostatnio wczytane dane i otwartą edycję. ${workspace.error}',
              ),
            ),
          workspace.when(
            skipError: true,
            data: _pageBody,
            error: (error, stack) => WorkspacePanel(
              title: 'Nie udało się wczytać danych',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.toString()),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Spróbuj ponownie'),
                  ),
                ],
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
