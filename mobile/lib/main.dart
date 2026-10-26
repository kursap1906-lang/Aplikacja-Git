import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/features/schedule/demo_schedule_page.dart';
import 'src/features/workspace/demo_attachments.dart';
import 'src/features/workspace/demo_collaboration.dart';
import 'src/core/api.dart';
import 'src/control_center_theme.dart';
import 'src/features/auth/backend_workspace_app.dart';
import 'src/features/workspace/workspace_shell.dart';
import 'src/features/workspace/role_catalog.dart';

void main() {
  usePathUrlStrategy();
  runApp(ProviderScope(child: ControlCenterEntry(initialUri: Uri.base)));
}

class ControlCenterEntry extends StatelessWidget {
  const ControlCenterEntry({required this.initialUri, super.key});

  final Uri initialUri;

  @override
  Widget build(BuildContext context) =>
      initialUri.path == '/demo' || initialUri.path == '/demo/'
      ? const ControlCenterApp()
      : BackendWorkspaceApp(initialUri: initialUri);
}

const demoNote =
    'DEMO — dane lokalne. Żadna operacja nie jest wysyłana do SDK ani GitHub.';

class Agent {
  Agent(
    this.id,
    this.name,
    this.role,
    this.account,
    this.plan,
    this.icon,
    this.task,
    this.used, {
    this.running = true,
    String? description,
  }) : description =
           description ??
           'Jesteś $name. Odpowiadasz za $role. Współpracujesz z zespołem, piszesz testy i raportujesz postęp.';
  final String id;
  String name, role, account, plan, task, description;
  final IconData icon;
  double used;
  bool running;
  final List<String> skills = [];
  final List<({String text, List<DemoFile> files})> messages = [];
  double get allowance => plan == 'Pro+' ? 70 : (plan == 'Max' ? 200 : 15);
  double get remaining => (allowance - used).clamp(0, double.infinity);
}

class Team {
  Team(
    this.id,
    this.name,
    this.repo,
    this.description,
    this.stage,
    this.progress,
    this.agentIds, {
    this.approval = false,
    this.completed = 0,
    this.pdf = 'MASTER_SPEC.pdf',
  });
  final String id;
  String name, repo, description, stage, pdf;
  double progress;
  List<String> agentIds;
  bool approval;
  int completed;
  final List<WorkTask> tasks = [];
  final List<({String stage, String instructions, List<DemoFile> files})>
  revisions = [];
  String prompt = '';
  String mainAccount = 'github-lead';
  final List<DemoFile> files = [];
  final Map<String, String> botAccounts = {};
  final Map<String, String> collaborationParents = {};
  String repositoryContext = '';
}

enum TaskPriority {
  low('Niski', Colors.blueGrey),
  normal('Normalny', Colors.blue),
  high('Wysoki', Colors.orange),
  urgent('Pilny', Colors.redAccent);

  const TaskPriority(this.label, this.color);
  final String label;
  final Color color;
}

class WorkTask {
  WorkTask(
    this.title,
    this.agentId, {
    this.status = 'Oczekuje',
    this.priority = TaskPriority.normal,
  });
  String title, agentId, status;
  TaskPriority priority;
}

class Integration {
  const Integration(
    this.id,
    this.name,
    this.group,
    this.icon,
    this.description,
    this.fields, {
    this.secret = false,
  });
  final String id, name, group, description;
  final IconData icon;
  final List<String> fields;
  final bool secret;
}

final initialIntegrations = <Integration>[
  const Integration(
    'github',
    'GitHub',
    'AI i GitHub',
    Icons.account_tree,
    'OAuth, repozytoria i Pull Requests',
    ['Właściciel', 'GitHub App ID'],
    secret: true,
  ),
  const Integration(
    'copilot',
    'Copilot SDK',
    'AI i GitHub',
    Icons.smart_toy,
    'Sesje agentów, narzędzia, streaming',
    ['Endpoint', 'Model'],
  ),
  const Integration(
    'openai',
    'OpenAI API',
    'AI i GitHub',
    Icons.auto_awesome,
    'Analiza PDF i generowanie planów',
    ['Model', 'Endpoint'],
    secret: true,
  ),
  const Integration(
    'postgres',
    'PostgreSQL / Supabase',
    'Bazy',
    Icons.storage,
    'Dane aplikacji i historia',
    ['Host', 'Nazwa bazy'],
    secret: true,
  ),
  const Integration('redis', 'Redis', 'Bazy', Icons.layers, 'Kolejki i cache', [
    'Redis URL',
  ], secret: true),
  const Integration(
    'storage',
    'Object Storage',
    'Bazy',
    Icons.folder_zip,
    'PDF, modele i artefakty',
    ['Endpoint', 'Bucket'],
    secret: true,
  ),
  const Integration(
    'docker',
    'Docker',
    'Serwer',
    Icons.dns,
    'Izolowane kontenery agentów',
    ['Adres usługi workera'],
  ),
  const Integration(
    'python',
    'Python',
    'Serwer',
    Icons.terminal,
    'Skrypty i obliczenia',
    ['Ścieżka do Python'],
  ),
  const Integration(
    'node',
    'Node.js',
    'Serwer',
    Icons.terminal,
    'Runtime TypeScript i JavaScript',
    ['Ścieżka do Node'],
  ),
  const Integration(
    'flutter',
    'Flutter SDK',
    'Serwer',
    Icons.phone_android,
    'Testowanie aplikacji',
    ['Ścieżka do Flutter'],
  ),
  const Integration(
    'blender',
    'Blender',
    'CAD i grafika',
    Icons.view_in_ar,
    'Modelowanie 3D i GLB',
    ['Ścieżka Blender', 'Tryb renderowania'],
  ),
  const Integration(
    'freecad',
    'FreeCAD',
    'CAD i grafika',
    Icons.straighten,
    'CAD i STEP/STL',
    ['Ścieżka do FreeCAD'],
  ),
  const Integration(
    'inkscape',
    'Inkscape',
    'CAD i grafika',
    Icons.draw,
    'Grafika wektorowa SVG',
    ['Ścieżka do Inkscape'],
  ),
  const Integration(
    'imagemagick',
    'ImageMagick',
    'CAD i grafika',
    Icons.image,
    'Przetwarzanie obrazów',
    ['Ścieżka do CLI'],
  ),
  const Integration(
    'ffmpeg',
    'FFmpeg',
    'CAD i grafika',
    Icons.movie,
    'Wideo i animacje',
    ['Ścieżka do CLI'],
  ),
  const Integration(
    'figma',
    'Figma',
    'CAD i grafika',
    Icons.design_services,
    'Makiety i grafiki UI',
    ['Workspace'],
    secret: true,
  ),
  const Integration(
    'playwright',
    'Playwright MCP',
    'MCP i Skills',
    Icons.web,
    'Testy przeglądarkowe',
    ['Komenda MCP'],
  ),
  const Integration(
    'filesystem',
    'Filesystem MCP',
    'MCP i Skills',
    Icons.folder_open,
    'Ograniczony dostęp do plików',
    ['Katalog roboczy'],
  ),
  const Integration(
    'context7',
    'Context7 MCP',
    'MCP i Skills',
    Icons.menu_book,
    'Dokumentacja programistyczna',
    ['Endpoint MCP'],
    secret: true,
  ),
  const Integration(
    'githubmcp',
    'GitHub MCP',
    'MCP i Skills',
    Icons.call_merge,
    'Narzędzia GitHub',
    ['Komenda MCP'],
    secret: true,
  ),
  const Integration(
    'security',
    'Security Skills',
    'MCP i Skills',
    Icons.security,
    'Audyt kodu',
    ['Katalog Skills'],
  ),
  const Integration(
    'actions',
    'GitHub Actions',
    'DevOps',
    Icons.account_tree,
    'Kompilacje i CI',
    ['Workflow'],
  ),
  const Integration(
    'sentry',
    'Sentry',
    'DevOps',
    Icons.bug_report,
    'Monitorowanie awarii',
    ['DSN'],
    secret: true,
  ),
  const Integration(
    'cloudflare',
    'Cloudflare',
    'DevOps',
    Icons.cloud,
    'DNS i domeny',
    ['Zone ID'],
    secret: true,
  ),
  const Integration('slack', 'Slack', 'Powiadomienia', Icons.chat, 'Alerty', [
    'Kanał',
  ], secret: true),
  const Integration(
    'discord',
    'Discord',
    'Powiadomienia',
    Icons.forum,
    'Alerty zespołowe',
    ['Kanał'],
    secret: true,
  ),
  const Integration(
    'telegram',
    'Telegram',
    'Powiadomienia',
    Icons.send,
    'Powiadomienia w telefonie',
    ['Chat ID'],
    secret: true,
  ),
  const Integration(
    'smtp',
    'SMTP',
    'Powiadomienia',
    Icons.email,
    'Wiadomości email',
    ['Host', 'Port', 'Nadawca'],
    secret: true,
  ),
  const Integration(
    'webhooks',
    'Webhooki',
    'Powiadomienia',
    Icons.webhook,
    'Własne zdarzenia',
    ['URL'],
    secret: true,
  ),
];

class ControlCenterApp extends StatefulWidget {
  const ControlCenterApp({this.logout, super.key});
  final Future<void> Function()? logout;

  @override
  State<ControlCenterApp> createState() => _ControlCenterAppState();
}

class _ControlCenterAppState extends State<ControlCenterApp> {
  bool _signedOut = false;

  Future<void> _logout() async {
    await (widget.logout ?? ApiClient().signOut)();
    if (mounted) setState(() => _signedOut = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Copilot Control Center',
    debugShowCheckedModeBanner: false,
    theme: controlCenterTheme(),
    home: _signedOut
        ? Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 48),
                    const SizedBox(height: 16),
                    const Text('Wylogowano'),
                    const SizedBox(height: 8),
                    const Text(
                      'Sesja konta została zakończona. Demonstracja jest publiczna.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _signedOut = false),
                      child: const Text('Otwórz demonstrację'),
                    ),
                  ],
                ),
              ),
            ),
          )
        : ControlCenter(onLogout: _logout),
  );
}

class ControlCenter extends StatefulWidget {
  const ControlCenter({this.onLogout, super.key});
  final Future<void> Function()? onLogout;
  @override
  State<ControlCenter> createState() => _ControlCenterState();
}

class _ControlCenterState extends State<ControlCenter> {
  final pages = workspaceNavigation;
  late final agents = <Agent>[
    Agent(
      'lead',
      'Tech Lead',
      'Architektura i koordynacja',
      'github-lead',
      'Pro',
      Icons.hub,
      'Kontrola zależności',
      4.8,
    ),
    Agent(
      'web',
      'Web Developer',
      'Next.js · React · TypeScript',
      'github-web',
      'Pro+',
      Icons.desktop_windows,
      'Podgląd CAD i 3D',
      52.4,
    ),
    Agent(
      'backend',
      'Backend Developer',
      'API · Supabase · PostgreSQL',
      'github-backend',
      'Pro+',
      Icons.storage,
      'API projektów',
      35.1,
    ),
    Agent(
      'mobile',
      'Mobile Developer',
      'React Native · Expo',
      'github-mobile',
      'Pro',
      Icons.phone_android,
      'Widoki mobilne',
      11.7,
      running: false,
    ),
    Agent(
      'cad',
      'CAD Engineer',
      'Geometria · FreeCAD',
      'github-cad',
      'Pro',
      Icons.architecture,
      'Walidacja geometrii',
      6.2,
    ),
    Agent(
      '3d',
      '3D Artist',
      'Blender · GLB',
      'github-3d',
      'Pro',
      Icons.view_in_ar,
      'Eksport modelu GLB',
      2.1,
      running: false,
    ),
    Agent(
      '2d',
      '2D Designer',
      'SVG · UI/UX',
      'github-2d',
      'Pro',
      Icons.palette,
      'Ikony i grafiki',
      1.3,
      running: false,
    ),
  ];
  late final teams = <Team>[
    Team(
      'build',
      'Asystent Budowlańca',
      'owner/asystent-budowlanca',
      'Aplikacja webowa i mobilna, kalkulatory, CAD i 3D',
      'Podgląd CAD i 3D',
      .75,
      ['lead', 'web', 'backend', 'mobile', 'cad', '3d', '2d'],
      approval: true,
      completed: 12,
    ),
    Team(
      'control',
      'Copilot Control Center',
      'owner/copilot-control-center',
      'Panel zarządzania agentami GitHub',
      'Integracja Copilot SDK',
      .36,
      ['lead', 'web', 'backend'],
      completed: 5,
    ),
    Team(
      'lab',
      'CAD & 3D Lab',
      'owner/cad-3d-lab',
      'Geometria, Blender i eksport GLB',
      'Walidacja eksportu',
      1,
      ['cad', '3d'],
      approval: true,
      completed: 9,
    ),
  ];
  final connected = <String>{
    'github',
    'copilot',
    'openai',
    'postgres',
    'filesystem',
    'playwright',
    'actions',
  };
  final enabled = <String>{};
  final toolConfigs = <String, Map<String, String>>{};
  final extraBudgets = <String, double>{'web': 20, 'backend': 10};
  final policies = <String, bool>{
    'Izolowane worktrees': true,
    'Zgoda przed merge': true,
    'Automatyczne delegacje': true,
    'Wspólna pamięć': true,
    'Cache PDF': true,
    'Quality Gate': true,
    'Blokowanie niezweryfikowanych MCP': true,
    'Dziennik audytu': true,
    'Powiadomienia push': true,
  };
  int page = 0, wizardStep = 0;
  String? _projectId;
  String _teamTab = 'Przegląd';
  bool _loggingOut = false;
  String? teamId, botId, editingId;
  bool approvalOnly = false, wizard = false;
  String roleBot = 'web',
      roleCategory = 'Programowanie',
      roleSearch = '',
      selectedIntegration = 'github',
      integrationCategory = 'Wszystkie',
      integrationSearch = '',
      settingsTab = 'Integracje';
  String budgetBot = 'web', routing = 'Zrównoważony';
  double monthlyLimit = 600;
  final chatController = TextEditingController(),
      teamName = TextEditingController(),
      teamRepo = TextEditingController(),
      teamDesc = TextEditingController(),
      teamPdf = TextEditingController(text: 'MASTER_SPEC.pdf'),
      teamTask = TextEditingController(),
      roleController = TextEditingController(),
      budgetController = TextEditingController(),
      accountController = TextEditingController();
  String accountPlan = 'Pro';
  final customRoles = <String>[];
  final combinedProfiles = <String>[];
  final combining = <String>{'web', 'mobile'};
  final roleGroups = botRoleCatalog;
  final accountExtras = <String>[];
  final _chatFiles = <String, List<DemoFile>>{};
  List<DemoFile> _draftFiles = [];
  List<WorkTask> _draftTasks = [];
  String? _taskBotId;
  String? get _selectedTaskBot =>
      _draftAgents.contains(_taskBotId) ? _taskBotId : _draftAgents.firstOrNull;
  Map<String, String> _draftAccounts = {};
  String _mainAccount = 'github-lead';
  List<String> get demoAccounts =>
      {...agents.map((agent) => agent.account), ...accountExtras}.toList();
  List<String> get demoRepositories => [
    for (final name in [
      'asystent-budowlanca',
      'copilot-control-center',
      'cad-3d-lab',
    ])
      '$_mainAccount/$name',
  ];
  Team? get team {
    for (final t in teams) {
      if (t.id == teamId) return t;
    }
    return null;
  }

  Agent? get bot {
    for (final a in agents) {
      if (a.id == botId) return a;
    }
    return null;
  }

  Agent get roleAgent => agents.firstWhere((a) => a.id == roleBot);
  Agent get budgetAgent => agents.firstWhere((a) => a.id == budgetBot);
  Integration get integration =>
      initialIntegrations.firstWhere((i) => i.id == selectedIntegration);
  void snack(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
  );
  void go(int index) {
    setState(() {
      page = index;
      teamId = null;
      _projectId = null;
      botId = null;
      approvalOnly = false;
    });
  }

  void openTeam(Team t) {
    setState(() {
      teamId = t.id;
      _projectId = null;
      _teamTab = 'Przegląd';
      botId = null;
      page = 0;
      approvalOnly = false;
    });
  }

  void beginWizard([Team? existing]) {
    editingId = existing?.id;
    teamName.text = existing?.name ?? 'Nowy zespół AI';
    _mainAccount = existing?.mainAccount ?? demoAccounts.first;
    teamRepo.text = existing?.repo ?? demoRepositories.first;
    teamDesc.text = existing?.description ?? '';
    teamPdf.text = existing?.pdf ?? '';
    teamTask.text = existing?.prompt ?? '';
    _draftFiles = [...?existing?.files];
    _draftTasks = [
      for (final task in existing?.tasks ?? <WorkTask>[])
        WorkTask(
          task.title,
          task.agentId,
          status: task.status,
          priority: task.priority,
        ),
    ];
    _draftAccounts = {
      for (final agent in agents)
        agent.id: existing?.botAccounts[agent.id] ?? agent.account,
    };
    _draftAgents = existing == null
        ? {'lead', 'web', 'backend'}
        : existing.agentIds.toSet();
    _taskBotId = _draftAgents.firstOrNull;
    setState(() {
      wizard = true;
      wizardStep = 0;
      page = 1;
    });
  }

  Set<String> _draftAgents = {'lead', 'web', 'backend'};
  void saveTeam() {
    if (teamName.text.trim().isEmpty || teamRepo.text.trim().isEmpty) {
      snack('Podaj nazwę i repozytorium');
      return;
    }
    if (_draftAgents.isEmpty) {
      snack('Wybierz co najmniej jednego bota.');
      return;
    }
    if (_draftTasks.any(
      (task) =>
          task.title.trim().isEmpty || !_draftAgents.contains(task.agentId),
    )) {
      snack('Każdy task musi mieć opis i bota wybranego w zespole.');
      return;
    }
    setState(() {
      Team target;
      if (editingId != null) {
        target = teams.firstWhere((t) => t.id == editingId);
        target.name = teamName.text;
        target.repo = teamRepo.text;
        target.description = teamDesc.text;
        target.pdf = teamPdf.text;
        target.agentIds = _draftAgents.toList();
      } else {
        target = Team(
          'team-${teams.length + 1}',
          teamName.text,
          teamRepo.text,
          teamDesc.text,
          'Planowanie',
          0,
          _draftAgents.toList(),
          pdf: teamPdf.text,
        );
        teams.add(target);
      }
      target.prompt = teamTask.text.trim();
      target.mainAccount = _mainAccount;
      target.files
        ..clear()
        ..addAll(_draftFiles);
      target.tasks
        ..clear()
        ..addAll(_draftTasks);
      target.botAccounts
        ..clear()
        ..addEntries(
          _draftAccounts.entries.where(
            (entry) => _draftAgents.contains(entry.key),
          ),
        );
      target.collaborationParents.removeWhere(
        (child, parent) =>
            !_draftAgents.contains(child) || !_draftAgents.contains(parent),
      );
      teamId = target.id;
      page = 0;
      wizard = false;
      botId = null;
      _projectId = null;
      _teamTab = 'Przegląd';
    });
    snack('Zapisano w prototypie');
  }

  @override
  void initState() {
    super.initState();
    teams[0].tasks.addAll([
      WorkTask('Podgląd belki 3D', 'web', status: 'Do akceptacji'),
      WorkTask('API konfiguracji', 'backend', status: 'Gotowe'),
      WorkTask('Obsługa mobilna', 'mobile', status: 'W trakcie'),
    ]);
    teams[1].tasks.addAll([
      WorkTask('Orkiestrator SDK', 'backend', status: 'W trakcie'),
      WorkTask('Kreator zespołów', 'web', status: 'W trakcie'),
    ]);
    teams[2].tasks.add(WorkTask('Eksport GLB', '3d', status: 'Do akceptacji'));
    for (final t in teams) {
      final leader = t.agentIds.first;
      t.collaborationParents.addEntries([
        for (final id in t.agentIds.skip(1)) MapEntry(id, leader),
      ]);
    }
  }

  @override
  void dispose() {
    for (final c in [
      chatController,
      teamName,
      teamRepo,
      teamDesc,
      teamPdf,
      teamTask,
      roleController,
      budgetController,
      accountController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget panel(String title, Widget child, {Widget? trailing}) =>
      WorkspacePanel(title: title, trailing: trailing, child: child);
  Widget info(
    String label,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Icon(icon, size: 19, color: Colors.white54),
              ],
            ),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    ),
  );
  Widget field(
    TextEditingController c,
    String title, {
    int lines = 1,
    String? hint,
  }) => TextField(
    controller: c,
    minLines: lines,
    maxLines: lines,
    decoration: InputDecoration(labelText: title, hintText: hint),
  );
  Widget action(
    String title,
    VoidCallback onPressed, {
    IconData icon = Icons.arrow_forward,
    bool outline = false,
  }) => outline
      ? OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(title),
        )
      : FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
          label: Text(title),
        );
  Widget statusChip(String label, {Color? color}) => Chip(
    visualDensity: VisualDensity.compact,
    label: Text(label, style: const TextStyle(fontSize: 11)),
    backgroundColor: (color ?? Colors.blueGrey).withValues(alpha: .18),
    side: BorderSide(color: (color ?? Colors.blueGrey).withValues(alpha: .32)),
  );
  Widget backToTeams() => action(
    'Lista zespołów',
    () {
      setState(() {
        teamId = null;
        botId = null;
        page = 0;
        _projectId = null;
        approvalOnly = false;
      });
    },
    icon: Icons.arrow_back,
    outline: true,
  );
  Future<void> openGitHub(String path) async {
    final uri = Uri.parse('https://github.com/settings/$path');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      snack('Nie udało się otworzyć GitHub');
    }
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await (widget.onLogout ?? ApiClient().signOut)();
    } on Exception catch (error) {
      if (mounted) snack('Nie udało się wylogować: $error');
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspaceShell(
    page: page,
    title: _projectId != null
        ? 'Szczegóły zadania'
        : bot != null
        ? bot!.name
        : team != null && page == 0
        ? team!.name
        : pages[page].$1,
    body: pageWidget(),
    banner: demoNote,
    status: 'DEMO',
    onNavigate: go,
    onLogout: _logout,
    loggingOut: _loggingOut,
    onNotifications: () => snack(demoNote),
    headerTrailing: team != null && page == 0 ? backToTeams() : null,
  );
  Widget pageWidget() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (page != 6)
        switch (page) {
          0 => dashboard(),
          1 => teamsPage(),
          2 => agentsPage(),
          3 => projectsPage(),
          4 => githubPage(),
          5 => budgetPage(),
          _ => settingsPage(),
        },
      Offstage(
        key: const ValueKey('calendar'),
        offstage: page != 6,
        child: DemoSchedulePage(
          agents: [
            for (final agent in agents) (id: agent.id, name: agent.name),
          ],
        ),
      ),
    ],
  );
  Widget dashboard() {
    if (team == null) {
      final pending = teams.where((t) => t.approval).toList();
      return Column(
        children: [
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Liczba botów',
                    '${agents.length + combinedProfiles.length}',
                    Icons.smart_toy,
                  ),
                ),
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Otwarte zadania',
                    '${teams.expand((t) => t.tasks).where((t) => t.status != 'Gotowe').length}',
                    Icons.task_alt,
                  ),
                ),
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Zakończone zadania',
                    '${teams.fold(0, (s, t) => s + t.completed)}',
                    Icons.check_circle,
                  ),
                ),
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Abonamenty miesięcznie',
                    '~525 zł',
                    Icons.wallet,
                  ),
                ),
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Zespoły czekające na potwierdzenie',
                    '${pending.length}',
                    Icons.fact_check,
                    onTap: () => setState(() => approvalOnly = true),
                  ),
                ),
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(
                    'Pozostałe kredyty AI',
                    '\$${agents.fold<double>(0, (s, a) => s + a.remaining).toStringAsFixed(2)}',
                    Icons.battery_full,
                    onTap: () => go(5),
                  ),
                ),
              ],
            ),
          ),
          panel(
            approvalOnly ? 'Zespoły do zatwierdzenia' : 'Twoje zespoły',
            Column(
              children: [
                if (approvalOnly)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => approvalOnly = false),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Wszystkie zespoły'),
                    ),
                  ),
                for (final t in (approvalOnly ? pending : teams)) ...[
                  _teamRow(t),
                  if (t.revisions.isNotEmpty) revisionNotes(t),
                  if (t.approval)
                    Wrap(
                      spacing: 8,
                      children: [
                        action(
                          'Zatwierdź',
                          () => decision(t, true),
                          icon: Icons.check,
                        ),
                        action(
                          'Do poprawek',
                          () => decision(t, false),
                          icon: Icons.edit,
                          outline: true,
                        ),
                      ],
                    ),
                  const Divider(),
                ],
                if (approvalOnly && pending.isEmpty)
                  const Text('Nie ma etapów oczekujących na akceptację.'),
              ],
            ),
          ),
        ],
      );
    }
    if (bot != null) return agentDetails(bot!);
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tab in [
              'Przegląd',
              'Profil projektu',
              'Zadania zespołu',
              'Współpraca',
              'Materiały',
            ])
              ChoiceChip(
                label: Text(tab),
                selected: _teamTab == tab,
                onSelected: (_) => setState(() => _teamTab = tab),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_teamTab == 'Zadania zespołu') teamTasks(team!),
        if (_teamTab == 'Profil projektu') repositoryProfile(team!),
        if (_teamTab == 'Współpraca')
          panel(
            'Graf współpracy',
            DemoCollaboration(
              members: [
                for (final a in agents.where(
                  (a) => team!.agentIds.contains(a.id),
                ))
                  (id: a.id, name: a.name, role: a.role),
              ],
              parents: team!.collaborationParents,
              onChanged: (parents) => setState(() {
                team!.collaborationParents
                  ..clear()
                  ..addAll(parents);
              }),
            ),
          ),
        if (_teamTab == 'Materiały') projectMaterials(team!),
        if (_teamTab == 'Przegląd') ...[
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, value, ic) in [
                  ('Boty', '${team!.agentIds.length}', Icons.smart_toy),
                  (
                    'Otwarte',
                    '${team!.tasks.where((t) => t.status != 'Gotowe').length}',
                    Icons.task_alt,
                  ),
                  ('Zakończone', '${team!.completed}', Icons.check_circle),
                  (
                    'Postęp',
                    '${(team!.progress * 100).round()}%',
                    Icons.trending_up,
                  ),
                ])
                  SizedBox(
                    width: cardWidth(c.maxWidth),
                    child: info(label, value, ic),
                  ),
              ],
            ),
          ),
          if (team!.approval)
            panel(
              'Wymaga Twojej akceptacji',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team!.stage),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      action(
                        'Zatwierdź etap',
                        () => decision(team!, true),
                        icon: Icons.check,
                      ),
                      action(
                        'Do poprawek',
                        () => decision(team!, false),
                        icon: Icons.edit,
                        outline: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (team!.revisions.isNotEmpty)
            panel('Uwagi do poprawek', revisionNotes(team!)),
          panel(
            'Aktywność zespołu',
            Column(
              children: [
                for (final a in agents.where(
                  (a) => team!.agentIds.contains(a.id),
                ))
                  ListTile(
                    leading: CircleAvatar(child: Icon(a.icon)),
                    title: Text(a.name),
                    subtitle: Text(
                      '${a.task} · ${team!.botAccounts[a.id] ?? a.account}\nPozostało \$${a.remaining.toStringAsFixed(2)}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => botId = a.id),
                  ),
                const Divider(),
                action(
                  'Edytuj zespół',
                  () => beginWizard(team),
                  icon: Icons.edit,
                  outline: true,
                ),
              ],
            ),
          ),
          panel(
            'Aktualny etap',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(team!.stage),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: team!.progress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(12),
                ),
                const SizedBox(height: 12),
                action(
                  'Zobacz zadania',
                  () => setState(() => _teamTab = 'Zadania zespołu'),
                ),
              ],
            ),
          ),
          teamTasks(team!),
        ],
      ],
    );
  }

  double cardWidth(double maxWidth) =>
      maxWidth > 680 ? (maxWidth - 20) / 2 : maxWidth;
  Widget _teamRow(Team t) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: const CircleAvatar(child: Icon(Icons.groups)),
    title: Text(t.name),
    subtitle: Text('${t.repo} · ${t.agentIds.length} botów\n${t.description}'),
    isThreeLine: true,
    trailing: const Icon(Icons.chevron_right),
    onTap: () => openTeam(t),
  );
  Widget revisionNotes(Team t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final revision in t.revisions) ...[
        ListTile(
          leading: const Icon(Icons.edit_note),
          title: Text('Do poprawek · ${revision.stage}'),
          subtitle: Text(revision.instructions),
        ),
        AttachmentList(files: revision.files),
      ],
    ],
  );

  Future<void> decision(Team t, bool yes) async {
    String? instructions;
    var files = <DemoFile>[];
    if (!yes) {
      final formKey = GlobalKey<FormState>();
      var draft = '';
      instructions = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text('Do poprawek · ${t.name}'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        autofocus: true,
                        minLines: 4,
                        maxLines: 8,
                        decoration: const InputDecoration(
                          labelText: 'Co zespół musi poprawić?',
                          hintText:
                              'Opisz wymagane zmiany i oczekiwany rezultat.',
                          alignLabelWithHint: true,
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Wpisz, co zespół musi poprawić.'
                            : null,
                        onSaved: (value) => draft = value!.trim(),
                      ),
                      const SizedBox(height: 12),
                      DemoAttachments(
                        files: files,
                        onChanged: (value) => updateDialog(() => files = value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  formKey.currentState!.save();
                  Navigator.of(dialogContext).pop(draft);
                },
                child: const Text('Przekaż do poprawek'),
              ),
            ],
          ),
        ),
      );
      if (!mounted || instructions == null) return;
    }
    setState(() {
      t.approval = false;
      if (!yes) {
        t.revisions.add((
          stage: t.stage,
          instructions: instructions!,
          files: [...files],
        ));
        t.progress = t.progress.clamp(0, .9);
      }
    });
    snack(yes ? 'Zatwierdzono etap (demo)' : 'Odesłano do poprawek (demo)');
  }

  Widget agentDetails(Agent a) => Column(
    children: [
      panel(
        'Agent · ${a.name}',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.role),
            Text(
              '${a.account} · Copilot ${a.plan}',
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            Text('Aktualnie: ${a.task}'),
            const SizedBox(height: 8),
            const LinearProgressIndicator(value: .58),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                action(
                  a.running ? 'Stop' : 'Wznów',
                  () => setState(() => a.running = !a.running),
                  icon: a.running ? Icons.stop : Icons.play_arrow,
                ),
                action(
                  'Logi SDK',
                  () => snack('Logi demonstracyjne; backend SDK niepodłączony'),
                  icon: Icons.receipt_long,
                  outline: true,
                ),
                action(
                  'Kredyty',
                  () {
                    setState(() {
                      budgetBot = a.id;
                      budgetController.text = '${extraBudgets[a.id] ?? 0}';
                      page = 5;
                    });
                  },
                  icon: Icons.wallet,
                  outline: true,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Status: ${a.running ? 'Pracuje' : 'Zatrzymany (demo)'}'),
          ],
        ),
      ),
      panel(
        'Kredyty i subskrypcja',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pozostało \$${a.remaining.toStringAsFixed(2)} / \$${a.allowance.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (a.used / a.allowance).clamp(0, 1)),
            const SizedBox(height: 10),
            action(
              'Zmień subskrypcję',
              () => openGitHub('copilot'),
              icon: Icons.open_in_new,
              outline: true,
            ),
          ],
        ),
      ),
      panel(
        'Czat z botem',
        Column(
          children: [
            ListTile(
              title: const Text('Bot · demo'),
              subtitle: Text(
                'Pracuję nad zadaniem: ${a.task}. Następnie uruchomię testy.',
              ),
            ),
            for (final msg in a.messages)
              ListTile(
                title: const Text('Ty'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.text),
                    AttachmentList(files: msg.files),
                  ],
                ),
              ),
            TextField(
              controller: chatController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Napisz do bota'),
            ),
            const SizedBox(height: 8),
            DemoAttachments(
              files: _chatFiles[a.id] ?? const [],
              onChanged: (files) => setState(() => _chatFiles[a.id] = files),
            ),
            action('Wyślij', () {
              if (chatController.text.trim().isEmpty &&
                  (_chatFiles[a.id]?.isEmpty ?? true)) {
                snack('Wpisz wiadomość lub dodaj plik.');
                return;
              }
              setState(() {
                a.messages.add((
                  text: chatController.text.trim(),
                  files: [...?_chatFiles[a.id]],
                ));
                _chatFiles.remove(a.id);
                chatController.clear();
              });
              snack('Wiadomość dodana do czatu demo');
            }, icon: Icons.send),
          ],
        ),
      ),
      panel(
        'Repozytorium i artefakty',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gałąź: agent/${a.id}/stage'),
            const Text(
              'Podgląd diff, terminala i testów zostanie podłączony do backendu.',
            ),
          ],
        ),
      ),
    ],
  );
  Widget teamsPage() => wizard
      ? teamWizard()
      : panel(
          'Wszystkie zespoły AI',
          Column(
            children: [
              for (final t in teams) ...[
                _teamRow(t),
                Align(
                  alignment: Alignment.centerRight,
                  child: action(
                    'Edytuj i zlecaj',
                    () => beginWizard(t),
                    icon: Icons.edit,
                    outline: true,
                  ),
                ),
                const Divider(),
              ],
              action('Utwórz zespół', () => beginWizard(), icon: Icons.add),
            ],
          ),
        );
  Widget teamWizard() => panel(
    editingId == null ? 'Nowy zespół AI' : 'Edytuj zespół AI',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: [
            for (var i = 0; i < 6; i++)
              ChoiceChip(
                label: Text(
                  ['Projekt', 'Boty', 'GitHub', 'PDF', 'Zadanie', 'Zapis'][i],
                ),
                selected: wizardStep == i,
                onSelected: (_) => setState(() => wizardStep = i),
              ),
          ],
        ),
        const SizedBox(height: 20),
        if (wizardStep == 0) ...[
          field(teamName, 'Nazwa zespołu'),
          const SizedBox(height: 12),
          const Text(
            'Konta i repozytoria demonstracyjne — lista nie jest pobierana z GitHub.',
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('main-account-$_mainAccount'),
            initialValue: _mainAccount,
            decoration: const InputDecoration(
              labelText: 'Główne konto GitHub (demo)',
            ),
            items: [
              for (final account in demoAccounts)
                DropdownMenuItem(value: account, child: Text(account)),
            ],
            onChanged: (account) {
              if (account == null) return;
              setState(() {
                _mainAccount = account;
                teamRepo.text = demoRepositories.first;
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('repo-$_mainAccount'),
            initialValue: teamRepo.text,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Wspólne repozytorium (demo)',
            ),
            items: [
              for (final repository in {...demoRepositories, teamRepo.text})
                DropdownMenuItem(value: repository, child: Text(repository)),
            ],
            onChanged: (repository) {
              if (repository != null) {
                setState(() => teamRepo.text = repository);
              }
            },
          ),
          const SizedBox(height: 12),
          field(teamDesc, 'Opis projektu', lines: 3),
        ] else if (wizardStep == 1) ...[
          const Text('Zaznacz boty zespołu:'),
          for (final a in agents)
            CheckboxListTile(
              value: _draftAgents.contains(a.id),
              title: Text(a.name),
              subtitle: Text(a.role),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _draftAgents.add(a.id);
                } else {
                  _draftAgents.remove(a.id);
                }
              }),
            ),
        ] else if (wizardStep == 2) ...[
          const Text(
            'Wybierz konto dla każdego bota — konta demonstracyjne, bez OAuth.',
          ),
          for (final a in agents.where((a) => _draftAgents.contains(a.id)))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey('account-${a.id}'),
                initialValue: _draftAccounts[a.id],
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: '${a.name} — konto GitHub (demo)',
                ),
                items: [
                  for (final account in demoAccounts)
                    DropdownMenuItem(value: account, child: Text(account)),
                ],
                onChanged: (account) {
                  if (account != null) {
                    setState(() => _draftAccounts[a.id] = account);
                  }
                },
              ),
            ),
          const Text('W wersji produkcyjnej konta podłączane są przez OAuth.'),
        ] else if (wizardStep == 3) ...[
          field(
            teamTask,
            'Pełny opis zadania dla zespołu',
            lines: 8,
            hint: 'Opisz cel, wymagania i oczekiwany rezultat. Dodaj PDF, obrazy lub inne pliki.',
          ),
          const SizedBox(height: 12),
          DemoAttachments(
            files: _draftFiles,
            onChanged: (files) => setState(() {
              _draftFiles = files;
              teamPdf.text = files.isEmpty
                  ? ''
                  : files.map((file) => file.name).join(', ');
            }),
          ),
        ] else if (wizardStep == 4) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in agents.where((a) => _draftAgents.contains(a.id)))
                ChoiceChip(
                  avatar: Icon(a.icon, size: 18),
                  label: Text(
                    '${a.name} (${_draftTasks.where((task) => task.agentId == a.id).length})',
                  ),
                  selected:
                      _taskBotId != '__unassigned__' &&
                      _selectedTaskBot == a.id,
                  onSelected: (_) => setState(() => _taskBotId = a.id),
                ),
              if (_draftTasks.any(
                (task) => !_draftAgents.contains(task.agentId),
              ))
                ActionChip(
                  avatar: const Icon(Icons.warning_amber),
                  label: const Text('Taski bez bota'),
                  onPressed: () =>
                      setState(() => _taskBotId = '__unassigned__'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Podziel zadanie na taski i przypisz je botom zespołu.'),
          Text(
            'Materiały z PDF: ${_draftFiles.length} plików. Opis: ${teamTask.text.trim().isEmpty ? "brak" : "dodany"}.',
          ),
          action(
            'Analizuj dokument przez AI',
            () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Analiza AI nie jest skonfigurowana'),
                content: const Text(
                  'Do automatycznego podziału opisu i załączników z kroku PDF na taski potrzebna jest konfiguracja usługi AI na serwerze. Pliki nie zostały wysłane ani przeanalizowane. Na razie dodaj i przypisz taski ręcznie.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Rozumiem'),
                  ),
                ],
              ),
            ),
            icon: Icons.auto_awesome,
            outline: true,
          ),
          if (_draftAgents.isEmpty)
            const Text('Najpierw wybierz boty w kroku Boty.'),
          if (_draftTasks
              .where(
                (task) => _taskBotId == '__unassigned__'
                    ? !_draftAgents.contains(task.agentId)
                    : task.agentId == _selectedTaskBot,
              )
              .isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Brak tasków dla wybranego bota. Dodaj pierwszy task poniżej.',
              ),
            ),
          for (final task in _draftTasks.where(
            (task) => _taskBotId == '__unassigned__'
                ? !_draftAgents.contains(task.agentId)
                : task.agentId == _selectedTaskBot,
          ))
            Card(
              key: ObjectKey(task),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: task.title,
                      decoration: const InputDecoration(
                        labelText: 'Opis taska',
                      ),
                      onChanged: (value) => task.title = value,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<TaskPriority>(
                      initialValue: task.priority,
                      decoration: const InputDecoration(labelText: 'Priorytet'),
                      items: [
                        for (final priority in TaskPriority.values)
                          DropdownMenuItem(
                            value: priority,
                            child: Text(
                              priority.label,
                              style: TextStyle(color: priority.color),
                            ),
                          ),
                      ],
                      onChanged: (priority) {
                        if (priority != null) {
                          setState(() => task.priority = priority);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: task.status,
                      decoration: const InputDecoration(
                        labelText: 'Status taska',
                      ),
                      items: [
                        for (final status in [
                          'Oczekuje',
                          'W trakcie',
                          'Do akceptacji',
                          'Gotowe',
                        ])
                          DropdownMenuItem(value: status, child: Text(status)),
                      ],
                      onChanged: (status) {
                        if (status != null) {
                          setState(() => task.status = status);
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${task.agentId}-${_draftAgents.join(",")}',
                      ),
                      initialValue: _draftAgents.contains(task.agentId)
                          ? task.agentId
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Bot odpowiedzialny',
                      ),
                      items: [
                        for (final a in agents.where(
                          (a) => _draftAgents.contains(a.id),
                        ))
                          DropdownMenuItem(value: a.id, child: Text(a.name)),
                      ],
                      onChanged: (id) {
                        if (id != null) {
                          setState(() {
                            task.agentId = id;
                            _taskBotId = id;
                          });
                        }
                      },
                    ),
                    TextButton.icon(
                      onPressed: () => setState(() => _draftTasks.remove(task)),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Usuń task'),
                    ),
                  ],
                ),
              ),
            ),
          action('Dodaj task', () {
            if (_draftAgents.isEmpty) {
              snack('Najpierw wybierz co najmniej jednego bota.');
              return;
            }
            setState(() {
              _taskBotId = _selectedTaskBot;
              _draftTasks.add(WorkTask('', _selectedTaskBot!));
            });
          }, icon: Icons.add),
        ] else ...[
          Text('Zespół: ${teamName.text}'),
          Text('Repozytorium: ${teamRepo.text}'),
          Text('Boty: ${_draftAgents.length}'),
          Text('Materiały: ${_draftFiles.length} plików'),
          Text('Opis zadania: ${teamTask.text}'),
          Text('Taski: ${_draftTasks.length}'),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            action(
              'Wstecz',
              () => setState(() => wizardStep = (wizardStep - 1).clamp(0, 5)),
              icon: Icons.arrow_back,
              outline: true,
            ),
            if (wizardStep < 5)
              action('Dalej', () => setState(() => wizardStep++))
            else
              action('Zapisz zespół', saveTeam, icon: Icons.save),
            action(
              'Zamknij',
              () => setState(() => wizard = false),
              icon: Icons.close,
              outline: true,
            ),
          ],
        ),
      ],
    ),
  );
  Future<void> addAgent() async {
    final form = GlobalKey<FormState>();
    var name = '', role = '', description = '';
    var account = demoAccounts.first;
    var plan = 'Pro';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dodaj własnego bota'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    decoration: const InputDecoration(labelText: 'Nazwa bota'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Podaj nazwę bota.';
                      }
                      if (agents.any(
                        (a) =>
                            a.name.toLowerCase() == value.trim().toLowerCase(),
                      )) {
                        return 'Bot o tej nazwie już istnieje.';
                      }
                      return null;
                    },
                    onSaved: (value) => name = value!.trim(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Rola i specjalizacja',
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Podaj rolę bota.'
                        : null,
                    onSaved: (value) => role = value!.trim(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Opis obowiązków',
                    ),
                    minLines: 3,
                    maxLines: 6,
                    onSaved: (value) => description = value!.trim(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: account,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Konto GitHub (demo)',
                    ),
                    items: [
                      for (final value in demoAccounts)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) {
                      if (value != null) account = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: plan,
                    decoration: const InputDecoration(labelText: 'Plan (demo)'),
                    items: [
                      for (final value in ['Pro', 'Pro+', 'Max'])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) {
                      if (value != null) plan = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Bot demonstracyjny. Nie uruchamia sesji SDK ani nie łączy konta GitHub.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              Navigator.pop(context, true);
            },
            child: const Text('Utwórz bota'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      final id = 'custom-${agents.length + 1}';
      agents.add(
        Agent(
          id,
          name,
          role,
          account,
          plan,
          Icons.smart_toy,
          'Oczekuje na przydział zadania',
          0,
          running: false,
          description: description.isEmpty ? null : description,
        ),
      );
      roleBot = id;
    });
    snack('Dodano własnego bota (demo). Możesz przypisać go do zespołu.');
  }

  Widget agentsPage() {
    if (bot != null) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => botId = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Lista botów'),
            ),
          ),
          agentDetails(bot!),
        ],
      );
    }
    final a = roleAgent;
    return Column(
      children: [
        panel(
          'Twoje boty',
          Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: action('Dodaj własnego bota', addAgent, icon: Icons.add),
              ),
              for (final agent in agents)
                ListTile(
                  leading: Icon(agent.icon),
                  title: Text(agent.name),
                  subtitle: Text('${agent.role} · ${agent.account}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() => botId = agent.id),
                ),
            ],
          ),
        ),
        panel(
          'Biblioteka specjalizacji',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final category in roleGroups.keys)
                    ChoiceChip(
                      label: Text(category),
                      selected: roleCategory == category,
                      onSelected: (_) =>
                          setState(() => roleCategory = category),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(labelText: 'Wyszukaj rolę'),
                onChanged: (v) => setState(() => roleSearch = v),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final role
                      in [...roleGroups[roleCategory]!, ...customRoles].where(
                        (s) =>
                            s.toLowerCase().contains(roleSearch.toLowerCase()),
                      ))
                    Chip(label: Text(role)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: roleController,
                      decoration: const InputDecoration(
                        labelText: 'Dodaj własną rolę',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      if (roleController.text.trim().isEmpty) return;
                      setState(
                        () => customRoles.add(roleController.text.trim()),
                      );
                      roleController.clear();
                    },
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
          ),
        ),
        panel(
          'Profil i obowiązki bota',
          Column(
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(roleBot),
                initialValue: roleBot,
                items: [
                  for (final b in agents)
                    DropdownMenuItem(value: b.id, child: Text(b.name)),
                ],
                onChanged: (v) => setState(() => roleBot = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('desc-${a.id}'),
                initialValue: a.description,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(labelText: 'Kim jest bot?'),
                onChanged: (v) => a.description = v,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  action('Generuj opis AI', () {
                    setState(
                      () => a.description =
                          'Ekspert ${a.role}. Analizuje wymagania, tworzy rozwiązania, testuje je i współpracuje z pozostałymi agentami.',
                    );
                    snack('Wstawiono przykładowy opis — bez OpenAI API');
                  }, icon: Icons.auto_awesome),
                  action(
                    'Zapisz',
                    () => snack('Profil zapisany w pamięci demo'),
                    icon: Icons.save,
                    outline: true,
                  ),
                ],
              ),
            ],
          ),
        ),
        panel(
          'Pluginy i MCP dostępne na serwerze (demo)',
          Column(
            children: [
              const Text(
                'Odblokuj narzędzie w Ustawieniach, a potem przypisz je botowi.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in initialIntegrations.where(
                    (i) => [
                      'AI i GitHub',
                      'MCP i Skills',
                      'CAD i grafika',
                    ].contains(i.group),
                  ))
                    FilterChip(
                      label: Text(item.name),
                      avatar: Icon(
                        connected.contains(item.id)
                            ? item.icon
                            : Icons.lock_outline,
                        size: 16,
                      ),
                      selected: a.skills.contains(item.id),
                      onSelected: (selected) {
                        if (!connected.contains(item.id)) {
                          snack(
                            'Narzędzie ${item.name} nie jest zweryfikowane na serwerze',
                          );
                          return;
                        }
                        setState(
                          () => selected
                              ? a.skills.add(item.id)
                              : a.skills.remove(item.id),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              action(
                'Otwórz integracje',
                () => go(7),
                icon: Icons.settings,
                outline: true,
              ),
            ],
          ),
        ),
        panel(
          'Łączenie wielu ról w jeden profil',
          Column(
            children: [
              for (final a in agents)
                CheckboxListTile(
                  dense: true,
                  title: Text(a.name),
                  value: combining.contains(a.id),
                  onChanged: (v) => setState(
                    () => v == true
                        ? combining.add(a.id)
                        : combining.remove(a.id),
                  ),
                ),
              const Text(
                'Łączymy specjalizacje, a nie licencje lub salda kont.',
              ),
              const SizedBox(height: 8),
              action('Połącz role', () {
                if (combining.length < 2) {
                  snack('Wybierz co najmniej 2 boty');
                  return;
                }
                setState(
                  () => combinedProfiles.add(
                    combining
                        .map((id) => agents.firstWhere((a) => a.id == id).name)
                        .join(' + '),
                  ),
                );
              }, icon: Icons.merge),
              for (final m in combinedProfiles) ListTile(title: Text(m)),
            ],
          ),
        ),
      ],
    );
  }

  Widget repositoryProfile(Team t) => panel(
    'Profil projektu · kontekst dla botów',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SelectableText('Repozytorium: ${t.repo}'),
        const SizedBox(height: 12),
        action(
          'Skanuj repozytorium z AI',
          () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text(
                'Skanowanie repozytorium nie jest skonfigurowane',
              ),
              content: const Text(
                'Wersja demonstracyjna nie pobiera plików z GitHub ani nie analizuje '
                'repozytorium przez AI. Wymaga to autoryzacji GitHub i konfiguracji '
                'usługi AI na serwerze. Skan nie został wykonany. '
                'Możesz ręcznie wpisać kontekst projektu poniżej i przekazać go botom lokalnie.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Rozumiem'),
                ),
              ],
            ),
          ),
          icon: Icons.manage_search,
          outline: true,
        ),
        const SizedBox(height: 12),
        const Text(
          'Kontekst projektu (ręczny, nie wynik skanowania). '
          'Opisz architekturę, technologie, ważne katalogi, zasady i polecenia testów. '
          'Dane pozostają lokalne i znikają po odświeżeniu.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey('repository-context-${t.id}'),
          initialValue: t.repositoryContext,
          minLines: 6,
          maxLines: 14,
          decoration: const InputDecoration(
            labelText: 'Kontekst repozytorium dla botów',
            alignLabelWithHint: true,
          ),
          onChanged: (value) => t.repositoryContext = value,
        ),
        const SizedBox(height: 12),
        Text(
          'Do przekazania: repozytorium, kontekst, opis zadania i ${t.files.length} załączników.',
        ),
        const SizedBox(height: 8),
        action(
          'Przekaż kontekst botom',
          () => shareRepositoryContext(t),
          icon: Icons.send,
        ),
      ],
    ),
  );

  Future<void> shareRepositoryContext(Team t) async {
    if (t.repositoryContext.trim().isEmpty) {
      snack('Najpierw wpisz kontekst repozytorium dla botów.');
      return;
    }
    if (t.agentIds.isEmpty) {
      snack('Najpierw dodaj boty do zespołu.');
      return;
    }
    final recipients = t.agentIds.toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          title: const Text('Przekaż kontekst botom (demo)'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Informacje trafią do lokalnego czatu wybranych botów. '
                    'Nie zostaną wysłane do SDK ani GitHub.',
                  ),
                  for (final a in agents.where(
                    (a) => t.agentIds.contains(a.id),
                  ))
                    CheckboxListTile(
                      title: Text(a.name),
                      value: recipients.contains(a.id),
                      onChanged: (selected) => updateDialog(() {
                        if (selected == true) {
                          recipients.add(a.id);
                        } else {
                          recipients.remove(a.id);
                        }
                      }),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: recipients.isEmpty
                  ? null
                  : () => Navigator.pop(context, true),
              child: const Text('Dodaj do czatów lokalnych'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      for (final a in agents.where((a) => recipients.contains(a.id))) {
        a.messages.add((
          text:
              'Kontekst projektu: ${t.name}\n'
              'Repozytorium: ${t.repo}\n\n'
              '${t.repositoryContext.trim()}\n\n'
              'Opis zadania: ${t.prompt.trim().isEmpty ? t.description : t.prompt.trim()}\n\n'
              'Twoje taski:\n${t.tasks.where((task) => task.agentId == a.id).map((task) => "- [${task.priority.label}] ${task.title} (${task.status})").join("\n")}',
          files: [...t.files],
        ));
      }
    });
    snack('Kontekst dodany do ${recipients.length} lokalnych czatów (demo).');
  }

  Widget projectMaterials(Team t) => panel(
    'Opis i materiały zadania',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Repozytorium: ${t.repo}'),
        Text('Etap: ${t.stage}'),
        const SizedBox(height: 12),
        Text(t.description),
        const SizedBox(height: 8),
        Text(t.prompt.isEmpty ? 'Brak szczegółowego opisu zadania.' : t.prompt),
        const SizedBox(height: 12),
        if (t.files.isEmpty) const Text('Brak załączników.'),
        AttachmentList(files: t.files),
        const SizedBox(height: 12),
        action(
          'Edytuj opis i materiały',
          () {
            beginWizard(t);
            setState(() => wizardStep = 3);
          },
          icon: Icons.edit,
          outline: true,
        ),
      ],
    ),
  );

  Widget projectsPage() {
    if (_projectId != null) {
      final t = teams.firstWhere((t) => t.id == _projectId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _projectId = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Lista projektów'),
            ),
          ),
          projectMaterials(t),
          panel(
            'Postęp zadania',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${(t.progress * 100).round()}% · ${t.stage}'),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: t.progress),
                if (t.revisions.isNotEmpty) revisionNotes(t),
              ],
            ),
          ),
          teamTasks(t),
          TextButton.icon(
            onPressed: () => openTeam(t),
            icon: const Icon(Icons.groups),
            label: const Text('Przejdź do zespołu'),
          ),
        ],
      );
    }
    return panel(
      'Specyfikacje PDF i etapy',
      Column(
        children: [
          for (final t in teams) ...[
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(t.name),
              subtitle: Text('${t.pdf}\n${t.stage}'),
              isThreeLine: true,
              trailing: Text('${(t.progress * 100).round()}%'),
              onTap: () => setState(() => _projectId = t.id),
            ),
            if (t.prompt.isNotEmpty) Text(t.prompt),
            AttachmentList(files: t.files),
            LinearProgressIndicator(value: t.progress),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget teamTasks(Team t) => panel(
    'Taski zespołu · ${t.name}',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.tasks.isEmpty) const Text('Brak tasków. Dodaj pierwszy task.'),
        for (final task in t.tasks)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(task.title),
            leading: Tooltip(
              message: 'Priorytet: ${task.priority.label}',
              child: Icon(Icons.flag, color: task.priority.color),
            ),
            subtitle: Text(
              '${agents.firstWhere((a) => a.id == task.agentId).name} · ${task.status} · ${task.priority.label}',
            ),
            onTap: () => editTask(t, task),
            trailing: IconButton(
              tooltip: 'Usuń task',
              onPressed: () => setState(() => t.tasks.remove(task)),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        action('Dodaj task zespołu', () => editTask(t), icon: Icons.add),
      ],
    ),
  );

  Future<void> editTask(Team t, [WorkTask? task]) async {
    if (t.agentIds.isEmpty) {
      snack('Najpierw dodaj bota do zespołu.');
      return;
    }
    final form = GlobalKey<FormState>();
    var title = task?.title ?? '';
    var agentId = task?.agentId ?? t.agentIds.first;
    var status = task?.status ?? 'Oczekuje';
    var priority = task?.priority ?? TaskPriority.normal;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(task == null ? 'Nowy task zespołu' : 'Edytuj task'),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: title,
                    decoration: const InputDecoration(labelText: 'Opis taska'),
                    minLines: 2,
                    maxLines: 5,
                    onSaved: (value) => title = value!.trim(),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Wpisz opis taska.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<TaskPriority>(
                    initialValue: priority,
                    decoration: const InputDecoration(labelText: 'Priorytet'),
                    items: [
                      for (final value in TaskPriority.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(value.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) priority = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: agentId,
                    decoration: const InputDecoration(
                      labelText: 'Bot odpowiedzialny',
                    ),
                    items: [
                      for (final a in agents.where(
                        (a) => t.agentIds.contains(a.id),
                      ))
                        DropdownMenuItem(value: a.id, child: Text(a.name)),
                    ],
                    onChanged: (value) {
                      if (value != null) agentId = value;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Status taska',
                    ),
                    items: [
                      for (final value in [
                        'Oczekuje',
                        'W trakcie',
                        'Do akceptacji',
                        'Gotowe',
                      ])
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) {
                      if (value != null) status = value;
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              Navigator.pop(context, true);
            },
            child: const Text('Zapisz task'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      if (task == null) {
        t.tasks.add(
          WorkTask(title, agentId, status: status, priority: priority),
        );
      } else {
        task.title = title;
        task.agentId = agentId;
        task.status = status;
        task.priority = priority;
      }
    });
  }

  Widget githubPage() => Column(
    children: [
      for (final t in teams)
        panel(
          t.repo,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.agentIds.length} agentów, osobne worktrees i branche'),
              const Text('Review + testy CI + zgoda przed merge do main'),
              const SizedBox(height: 10),
              action(
                'Otwórz zespół',
                () => openTeam(t),
                icon: Icons.arrow_forward,
                outline: true,
              ),
            ],
          ),
        ),
      panel(
        'GitHub',
        Column(
          children: [
            const Text('Połącz GitHub App i API w Ustawieniach.'),
            const SizedBox(height: 10),
            action('Konfiguruj GitHub', () {
              go(7);
              setState(() => selectedIntegration = 'github');
            }, icon: Icons.settings),
          ],
        ),
      ),
    ],
  );
  Widget budgetPage() {
    final a = budgetAgent;
    final totalSubscription = agents.fold<double>(
      0,
      (s, a) => s + (a.plan == 'Pro+' ? 39 : 10),
    );
    final totalCredits = agents.fold<double>(0, (s, a) => s + a.allowance);
    final left = agents.fold<double>(0, (s, a) => s + a.remaining);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in [
                ('Abonamenty', '\$${totalSubscription.toStringAsFixed(0)}'),
                ('Kredyty planów', '\$${totalCredits.toStringAsFixed(0)}'),
                ('Pozostało', '\$${left.toStringAsFixed(2)}'),
                (
                  'Dodatkowe limity',
                  '\$${extraBudgets.values.fold<double>(0, (x, y) => x + y).toStringAsFixed(0)}',
                ),
              ])
                SizedBox(
                  width: cardWidth(c.maxWidth),
                  child: info(m.$1, m.$2, Icons.account_balance_wallet),
                ),
            ],
          ),
        ),
        panel(
          'Kredyty na konto',
          Column(
            children: [
              for (final a in agents)
                InkWell(
                  onTap: () => setState(() {
                    budgetBot = a.id;
                    budgetController.text = '${extraBudgets[a.id] ?? 0}';
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('${a.name} · ${a.plan}')),
                            Text(
                              '\$${a.remaining.toStringAsFixed(2)} / \$${a.allowance.toStringAsFixed(2)}',
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (a.used / a.allowance).clamp(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        panel(
          'Subskrypcja i dodatkowy budżet: ${a.name}',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a.account} · ${a.plan}'),
              const SizedBox(height: 8),
              Text('Pozostało: \$${a.remaining.toStringAsFixed(2)}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  action(
                    'Zmień subskrypcję',
                    () => openGitHub('copilot'),
                    icon: Icons.open_in_new,
                  ),
                  action(
                    'Budżet w GitHub',
                    () => openGitHub('billing'),
                    icon: Icons.open_in_new,
                    outline: true,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              field(budgetController, 'Dodatkowy limit (USD)'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final n in [0, 5, 10, 20, 50])
                    OutlinedButton(
                      onPressed: () => budgetController.text = '$n',
                      child: Text('\$$n'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              action('Zapisz lokalny budżet', () {
                final v = double.tryParse(budgetController.text);
                if (v == null || v < 0) {
                  snack('Nieprawidłowa kwota');
                  return;
                }
                setState(() => extraBudgets[a.id] = v);
                snack('Zmieniono tylko limit prototypu');
              }, icon: Icons.save),
            ],
          ),
        ),
        panel(
          'Optymalizacja wydatków',
          Column(
            children: [
              Text('Limit organizacji: ${monthlyLimit.round()} zł'),
              Slider(
                value: monthlyLimit,
                min: 300,
                max: 1500,
                divisions: 24,
                onChanged: (v) => setState(() => monthlyLimit = v),
              ),
              for (final m in [
                'Ekonomiczny',
                'Zrównoważony',
                'Najwyższa jakość',
              ])
                RadioListTile<String>(
                  title: Text(m),
                  value: m,
                  groupValue: routing,
                  onChanged: (v) => setState(() => routing = v!),
                ),
              const Text(
                'Dane kredytów są demonstracyjne. W produkcji pochodzą z informacji rozliczeniowych GitHub.',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget settingsPage() => Column(
    children: [
      panel(
        'Centrum ustawień',
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in [
              'Integracje',
              'Konta GitHub',
              'Serwer i MCP',
              'Automatyzacje',
              'Bezpieczeństwo',
            ])
              ChoiceChip(
                label: Text(t),
                selected: settingsTab == t,
                onSelected: (_) => setState(() => settingsTab = t),
              ),
          ],
        ),
      ),
      if (settingsTab == 'Integracje')
        integrationsPage()
      else if (settingsTab == 'Konta GitHub')
        accountsPage()
      else if (settingsTab == 'Serwer i MCP')
        serverPage()
      else
        policiesPage(),
    ],
  );
  Widget integrationsPage() {
    final groups = [
      'Wszystkie',
      ...{for (final i in initialIntegrations) i.group},
    ];
    final shown = initialIntegrations
        .where(
          (i) =>
              (integrationCategory == 'Wszystkie' ||
                  i.group == integrationCategory) &&
              (i.name + ' ' + i.description).toLowerCase().contains(
                integrationSearch.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => Wrap(
            spacing: 8,
            children: [
              SizedBox(
                width: cardWidth(c.maxWidth),
                child: info(
                  'Integracje',
                  '${initialIntegrations.length}',
                  Icons.extension,
                ),
              ),
              SizedBox(
                width: cardWidth(c.maxWidth),
                child: info(
                  'Połączone (demo)',
                  '${connected.length}',
                  Icons.check_circle,
                ),
              ),
            ],
          ),
        ),
        panel(
          'Katalog integracji',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Szukaj integracji',
                ),
                onChanged: (v) => setState(() => integrationSearch = v),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final g in groups)
                    ChoiceChip(
                      label: Text(g),
                      selected: integrationCategory == g,
                      onSelected: (_) =>
                          setState(() => integrationCategory = g),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final i in shown)
                    SizedBox(
                      width: 165,
                      child: InkWell(
                        onTap: () => setState(() => selectedIntegration = i.id),
                        child: Card(
                          color: selectedIntegration == i.id
                              ? const Color(0xff283554)
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(i.icon),
                                const SizedBox(height: 8),
                                Text(i.name, maxLines: 2),
                                const SizedBox(height: 6),
                                statusChip(
                                  connected.contains(i.id)
                                      ? 'Połączono (demo)'
                                      : 'Niepołączono',
                                  color: connected.contains(i.id)
                                      ? Colors.green
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (shown.isEmpty) const Text('Brak wyników.'),
            ],
          ),
        ),
        panel(
          'Konfiguracja: ${integration.name}',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(integration.description),
              const SizedBox(height: 14),
              for (final f in integration.fields) ...[
                TextFormField(
                  key: ValueKey('${integration.id}:$f'),
                  initialValue: toolConfigs[integration.id]?[f] ?? '',
                  onChanged: (v) =>
                      toolConfigs.putIfAbsent(integration.id, () => {})[f] = v,
                  decoration: InputDecoration(labelText: f),
                ),
                const SizedBox(height: 10),
              ],
              if (integration.secret) ...[
                TextFormField(
                  key: ValueKey('${integration.id}:secret'),
                  obscureText: true,
                  onChanged: (v) => toolConfigs.putIfAbsent(
                    integration.id,
                    () => {},
                  )['secret'] = v,
                  decoration: const InputDecoration(
                    labelText: 'Klucz / token — tylko demo',
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nie wpisuj prawdziwych sekretów w prototyp.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ],
              SwitchListTile(
                title: const Text('Udostępnij botom'),
                value: enabled.contains(integration.id),
                onChanged: (v) => setState(
                  () => v
                      ? enabled.add(integration.id)
                      : enabled.remove(integration.id),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  action(
                    connected.contains(integration.id) ? 'Rozłącz' : 'Połącz',
                    () => setState(
                      () => connected.contains(integration.id)
                          ? connected.remove(integration.id)
                          : connected.add(integration.id),
                    ),
                    icon: Icons.power_settings_new,
                  ),
                  action(
                    'Testuj',
                    () => snack('Test symulowany, brak połączenia z serwerem'),
                    icon: Icons.network_check,
                    outline: true,
                  ),
                  action(
                    'Zapisz',
                    () => snack('Zapisano konfigurację w pamięci demo'),
                    icon: Icons.save,
                    outline: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget accountsPage() => panel(
    'Konta GitHub i plany',
    Column(
      children: [
        for (final a in agents)
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(a.account),
            subtitle: Text('${a.name} · ${a.plan}'),
            trailing: TextButton(
              onPressed: () {
                setState(() {
                  budgetBot = a.id;
                  budgetController.text = '${extraBudgets[a.id] ?? 0}';
                  page = 5;
                });
              },
              child: const Text('Kredyty'),
            ),
          ),
        for (final a in accountExtras)
          ListTile(
            title: Text(a),
            subtitle: const Text('Nieprzypisane konto demonstracyjne'),
          ),
        const Divider(),
        field(accountController, 'Nowy login GitHub'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: accountPlan,
          items: [
            'Pro',
            'Pro+',
            'Business',
            'Enterprise',
          ].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
          onChanged: (v) => accountPlan = v!,
        ),
        const SizedBox(height: 12),
        action('Dodaj konto', () {
          if (accountController.text.trim().isEmpty) return;
          setState(() => accountExtras.add(accountController.text.trim()));
          accountController.clear();
        }, icon: Icons.add),
      ],
    ),
  );
  Widget serverPage() => panel(
    'Serwer i MCP',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Stan serwera: niepodłączony — nie weryfikujemy zainstalowanych narzędzi.',
        ),
        const SizedBox(height: 12),
        for (final i in initialIntegrations.where(
          (i) => ['Serwer', 'MCP i Skills', 'CAD i grafika'].contains(i.group),
        ))
          ListTile(
            leading: Icon(i.icon),
            title: Text(i.name),
            subtitle: Text(
              connected.contains(i.id) ? 'Demo: połączono' : 'Niezweryfikowane',
            ),
            trailing: TextButton(
              onPressed: () {
                setState(() {
                  settingsTab = 'Integracje';
                  selectedIntegration = i.id;
                });
              },
              child: const Text('Konfiguruj'),
            ),
          ),
        action(
          'Skanuj serwer',
          () => snack('Wymagany backend i agent narzędziowy na VPS'),
          icon: Icons.search,
        ),
      ],
    ),
  );
  Widget policiesPage() => panel(
    settingsTab,
    Column(
      children: [
        for (final key in policies.keys.where(
          (k) => settingsTab == 'Bezpieczeństwo'
              ? [
                  'Izolowane worktrees',
                  'Zgoda przed merge',
                  'Blokowanie niezweryfikowanych MCP',
                  'Dziennik audytu',
                ].contains(k)
              : true,
        ))
          SwitchListTile(
            title: Text(key),
            value: policies[key]!,
            onChanged: (v) => setState(() => policies[key] = v),
          ),
        action(
          'Zapisz ustawienia',
          () => snack('Zapisano ustawienia demonstracyjne'),
          icon: Icons.save,
        ),
      ],
    ),
  );
}
