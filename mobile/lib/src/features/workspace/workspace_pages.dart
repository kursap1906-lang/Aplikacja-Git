import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class BotsPage extends ConsumerWidget {
  const BotsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Boty i role',
      subtitle: 'Agenci, ich repozytoria i postęp etapów.',
      action: FilledButton.icon(
        onPressed: () => context.go('/bots/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Dodaj bota'),
      ),
      children: [
        bots.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(botsProvider),
          ),
          data: (items) => items.isEmpty
              ? const _InformationCard(
                  icon: Icons.smart_toy_outlined,
                  title: 'Nie ma jeszcze botów',
                  body: 'Połącz konto GitHub i utwórz pierwszego bota dla repozytorium.',
                )
              : Column(
                  children: [
                    for (final bot in items)
                      _BotCard(bot: bot, onTap: () => context.go('/bots/${bot['id']}')),
                  ],
                ),
        ),
      ],
    );
  }
}

class TeamsPage extends StatelessWidget {
  const TeamsPage({super.key});

  @override
  Widget build(BuildContext context) => const _PageFrame(
        title: 'Zespoły AI',
        subtitle: 'Boty, repozytoria i polityki przypisane do zespołu.',
        children: [
          _InformationCard(
            icon: Icons.groups_outlined,
            title: 'Zespoły nie są jeszcze zapisywane przez API',
            body: 'W tej wersji aplikacji nie ma trwałego modelu zespołów ani endpointów przypisywania botów. Nie pokazujemy fikcyjnych zespołów ani przycisku, który nie zapisuje zmian.',
            warning: true,
          ),
        ],
      );
}

class RepositoriesPage extends ConsumerStatefulWidget {
  const RepositoriesPage({super.key});

  @override
  ConsumerState<RepositoriesPage> createState() => _RepositoriesPageState();
}

class _RepositoriesPageState extends ConsumerState<RepositoriesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionDataProvider);
    return _PageFrame(
      title: 'Repozytoria',
      subtitle: 'Repozytoria pobrane na żądanie z połączonych kont GitHub.',
      children: [
        TextField(
          controller: _search,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            labelText: 'Szukaj repozytorium',
          ),
        ),
        const SizedBox(height: 14),
        session.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(sessionDataProvider),
          ),
          data: (data) {
            final accounts = _records(data['githubAccounts']);
            if (accounts.isEmpty) {
              return const _InformationCard(
                icon: Icons.link_off_rounded,
                title: 'Połącz konto GitHub, aby zobaczyć repozytoria',
                body: 'Repozytoria są pobierane bezpośrednio z GitHub po autoryzacji użytkownika.',
              );
            }
            return Column(
              children: [
                for (final account in accounts)
                  _RepositoriesForAccount(
                    account: account,
                    query: _query,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RepositoriesForAccount extends ConsumerWidget {
  const _RepositoriesForAccount({required this.account, required this.query});

  final Map<String, dynamic> account;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = account['id']?.toString() ?? '';
    if (account['status'] != 'ACTIVE') {
      return _InformationCard(
        icon: Icons.lock_clock_outlined,
        title: '@${account['login'] ?? 'GitHub'} wymaga ponownej autoryzacji',
        body: 'Połącz ponownie konto w sekcji Konta GitHub, aby bezpiecznie odświeżyć listę repozytoriów.',
        warning: true,
      );
    }

    final repositories = ref.watch(githubRepositoriesProvider(id));
    return repositories.when(
      loading: () => _AccountRepositoryGroup(
        title: '@${account['login']}',
        child: const LinearProgressIndicator(),
      ),
      error: (error, stack) => _AccountRepositoryGroup(
        title: '@${account['login']}',
        child: _ErrorCard(
          message: error.toString(),
          onRetry: () => ref.invalidate(githubRepositoriesProvider(id)),
        ),
      ),
      data: (items) {
        final filtered = items.where((repository) {
          final name = repository['fullName']?.toString().toLowerCase() ?? '';
          return name.contains(query);
        }).toList();
        return _AccountRepositoryGroup(
          title: '@${account['login']} · ${filtered.length}',
          child: filtered.isEmpty
              ? Text(
                  items.isEmpty
                      ? 'GitHub nie zwrócił repozytoriów dla tego konta.'
                      : 'Brak repozytoriów pasujących do wyszukiwania.',
                  style: const TextStyle(color: AppColors.muted),
                )
              : Column(
                  children: [
                    for (final repository in filtered)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          repository['isPrivate'] == true
                              ? Icons.lock_outline_rounded
                              : Icons.public_rounded,
                          color: AppColors.blue,
                        ),
                        title: Text(repository['fullName']?.toString() ?? ''),
                        subtitle: Text(
                          'Domyślna gałąź: ${repository['defaultBranch'] ?? 'nieznana'} · ${repository['canPush'] == true ? 'zapis dozwolony' : 'tylko odczyt'}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12),
                        ),
                        trailing: repository['canPush'] == true
                            ? const Icon(Icons.edit_outlined, color: AppColors.mint)
                            : const Icon(Icons.visibility_outlined, color: AppColors.muted),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Projekty i PDF',
      subtitle: 'Repozytoria i dokumenty wykorzystywane podczas planowania pracy.',
      children: [
        const _InformationCard(
          icon: Icons.description_outlined,
          title: 'Przechowywanie PDF nie jest jeszcze skonfigurowane',
          body: 'API nie ma magazynu dokumentów, wersjonowania ani bezpiecznego indeksowania. Przesyłanie i generowanie wymagań pozostaje niedostępne; treść dokumentów nie jest wykonywana jako polecenia.',
          warning: true,
        ),
        const SizedBox(height: 12),
        bots.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(botsProvider),
          ),
          data: (items) => items.isEmpty
              ? const _InformationCard(
                  icon: Icons.folder_open_outlined,
                  title: 'Brak powiązanych repozytoriów',
                  body: 'Repozytoria projektów pojawią się tutaj po utworzeniu bota.',
                )
              : Column(
                  children: [
                    for (final bot in items)
                      _BotCard(
                        bot: bot,
                        onTap: () => context.go('/bots/${bot['id']}'),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  final _search = TextEditingController();
  String _query = '';
  String _status = 'ALL';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Zadania i etapy',
      subtitle: 'Postęp etapów zapisanych dla Twoich botów.',
      action: FilledButton.icon(
        onPressed: () => context.go('/bots/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nowe zadanie'),
      ),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Szukaj zadań',
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'ALL', child: Text('Wszystkie statusy')),
                  DropdownMenuItem(value: 'PENDING', child: Text('Oczekujące')),
                  DropdownMenuItem(value: 'RUNNING', child: Text('W trakcie')),
                  DropdownMenuItem(value: 'WAITING_APPROVAL', child: Text('Do review')),
                  DropdownMenuItem(value: 'APPROVED', child: Text('Zatwierdzone')),
                  DropdownMenuItem(value: 'CHANGES_REQUESTED', child: Text('Do poprawek')),
                  DropdownMenuItem(value: 'FAILED', child: Text('Błąd')),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'ALL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        bots.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(botsProvider),
          ),
          data: (items) {
            final tasks = <Map<String, dynamic>>[];
            for (final bot in items) {
              for (final stage in _records(bot['stages'])) {
                final status = stage['status']?.toString() ?? '';
                final searchable = [
                  stage['title'],
                  stage['description'],
                  bot['name'],
                  bot['repository'],
                ].join(' ').toLowerCase();
                if ((_status == 'ALL' || status == _status) && searchable.contains(_query)) {
                  tasks.add({
                    ...stage,
                    'botId': bot['id'],
                    'botName': bot['name'],
                    'repository': bot['repository'],
                  });
                }
              }
            }
            if (tasks.isEmpty) {
              return const _InformationCard(
                icon: Icons.task_alt_outlined,
                title: 'Brak pasujących zadań',
                body: 'Zmień filtr albo utwórz bota, aby dodać etap.',
              );
            }
            return Column(
              children: [
                for (final task in tasks)
                  _TaskCard(
                    task: task,
                    onTap: () => context.go('/bots/${task['botId']}'),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CollaborationPage extends StatelessWidget {
  const CollaborationPage({super.key});

  @override
  Widget build(BuildContext context) => const _PageFrame(
        title: 'Współpraca',
        subtitle: 'Wiadomości, checkpointy i prośby o pomoc między agentami.',
        children: [
          _InformationCard(
            icon: Icons.forum_outlined,
            title: 'Kanały i checkpointy wymagają backendu współpracy',
            body: 'Aplikacja nie zapisuje wiadomości, checkpointów ani zadań pomocniczych. Nie udostępniamy przycisku wysyłania, dopóki zapis i wznowienie kontekstu nie są trwałe.',
            warning: true,
          ),
        ],
      );
}

class PullRequestsPage extends ConsumerWidget {
  const PullRequestsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Pull Requesty',
      subtitle: 'Pull requesty powiązane z etapami botów.',
      children: [
        bots.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(botsProvider),
          ),
          data: (items) {
            final requests = <Map<String, dynamic>>[];
            for (final bot in items) {
              for (final stage in _records(bot['stages'])) {
                for (final request in _records(stage['pullRequests'])) {
                  requests.add({
                    ...request,
                    'botId': bot['id'],
                    'botName': bot['name'],
                    'stageTitle': stage['title'],
                    'repository': bot['repository'],
                  });
                }
              }
            }
            if (requests.isEmpty) {
              return const _InformationCard(
                icon: Icons.merge_type_outlined,
                title: 'Nie znaleziono pull requestów',
                body: 'Połączone PR-y pojawią się po synchronizacji pracy agenta.',
              );
            }
            return Column(
              children: [
                for (final request in requests)
                  _PullRequestCard(
                    request: request,
                    onOpen: () => context.go(
                      '/bots/${request['botId']}/pull-requests/${request['id']}',
                    ),
                    onGitHub: () => _openGitHubUrl(context, request['url']),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CodeCenterPage extends ConsumerWidget {
  const CodeCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _PageFrame(
        title: 'Code Center',
        subtitle: 'Otwórz autoryzowany workspace VS Code na obecnym hostingu.',
        children: [
          _InformationCard(
            icon: Icons.code_rounded,
            title: kIsWeb ? 'Edytor działa w osobnym workspace' : 'Edytor jest dostępny w przeglądarce',
            body: kIsWeb
                ? 'Otworzy się skonfigurowany edytor code-server. W tej wersji repozytorium i gałąź wybiera się wewnątrz workspace; aplikacja nie udaje, że przełącza gałąź ani otwiera preview.'
                : 'Otwórz aplikację w przeglądarce, aby uruchomić autoryzowany workspace VS Code.',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: kIsWeb ? () => _openEditor(context, ref) : null,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Otwórz w Visual Studio Code'),
            ),
          ),
          const SizedBox(height: 12),
          const _InformationCard(
            icon: Icons.info_outline_rounded,
            title: 'Testy i zmiany Git',
            body: 'Wykonywanie poleceń w izolowanym runnerze, zapisywanie zmian w repozytorium i tworzenie PR nie są udostępniane przez backend tej aplikacji.',
            warning: true,
          ),
        ],
      );
}

class ReviewCenterPage extends ConsumerWidget {
  const ReviewCenterPage({required this.selectedStageId, super.key});

  final String? selectedStageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Review Center',
      subtitle: 'Przeglądaj rzeczywiste etapy i dowody przed decyzją.',
      children: [
        const _InformationCard(
          icon: Icons.verified_user_outlined,
          title: 'Zatwierdzanie etapu jest zablokowane',
          body: 'Wymagane: CI potwierdzone przez serwer, aktualne preview przypięte do dokładnych SHA, zapisane testy manualne i uprawnienia recenzenta. Te dowody nie są jeszcze przechowywane w API, więc sam status etapu ani kliknięcie w UI nie wystarczają.',
          warning: true,
        ),
        const SizedBox(height: 12),
        bots.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(botsProvider),
          ),
          data: (items) {
            final stages = <Map<String, dynamic>>[];
            for (final bot in items) {
              for (final stage in _records(bot['stages'])) {
                final isSelected = stage['id'] == selectedStageId;
                if (selectedStageId == null ||
                    isSelected ||
                    stage['status'] == 'WAITING_APPROVAL') {
                  stages.add({
                    ...stage,
                    'botId': bot['id'],
                    'botName': bot['name'],
                    'repository': bot['repository'],
                  });
                }
              }
            }
            if (stages.isEmpty) {
              return const _InformationCard(
                icon: Icons.fact_check_outlined,
                title: 'Brak etapów wymagających review',
                body: 'Etapy pojawią się tutaj po przypisaniu ich do botów.',
              );
            }
            return Column(
              children: [
                for (final stage in stages)
                  _ReviewStageCard(
                    stage: stage,
                    onOpenBot: () => context.go('/bots/${stage['botId']}'),
                    onOpenEditor: () => _openEditor(context, ref),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class SchedulePage extends StatelessWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context) => const _PageFrame(
        title: 'Harmonogram pracy',
        subtitle: 'Godziny pracy agentów, wyjątki i polityki checkpointów.',
        children: [
          _InformationCard(
            icon: Icons.calendar_month_outlined,
            title: 'Harmonogramy nie wpływają jeszcze na wykonanie zadań',
            body: 'Backend nie przechowuje reguł godzinowych ani wyjątków. Zapisanie samego formularza bez kolejki zadań byłoby mylące, dlatego harmonogram jest wyłączony.',
            warning: true,
          ),
        ],
      );
}

class CostsPage extends StatelessWidget {
  const CostsPage({super.key});

  @override
  Widget build(BuildContext context) => const _PageFrame(
        title: 'Koszty AI',
        subtitle: 'Rzeczywiste zużycie tokenów, budżety i koszty stałe.',
        children: [
          _InformationCard(
            icon: Icons.payments_outlined,
            title: 'Dane kosztowe nie są dostępne',
            body: 'GitHub Agent Tasks nie udostępnia w tej integracji zużycia tokenów ani stawek. Bez źródła rozliczeń nie pokazujemy prognoz jako kosztów rzeczywistych ani fikcyjnych budżetów.',
            warning: true,
          ),
        ],
      );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.children,
    this.action,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(26, 25, 26, 36),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.blue,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(title, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 5),
                    Text(subtitle, style: const TextStyle(color: AppColors.muted)),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 12),
                action!,
              ],
            ],
          ),
          const SizedBox(height: 22),
          ...children,
        ],
      );
}

class _InformationCard extends StatelessWidget {
  const _InformationCard({
    required this.icon,
    required this.title,
    required this.body,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.amber : AppColors.blue;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(body, style: const TextStyle(color: AppColors.muted, height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: LinearProgressIndicator(),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_outlined, color: AppColors.coral),
              const SizedBox(width: 10),
              Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted))),
              IconButton(
                tooltip: 'Ponów',
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
      );
}

class _BotCard extends StatelessWidget {
  const _BotCard({required this.bot, required this.onTap});

  final Map<String, dynamic> bot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stages = _records(bot['stages']);
    final activeStages = stages.where((stage) => stage['status'] != 'APPROVED').length;
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.panelRaised,
          child: Icon(Icons.smart_toy_outlined, color: AppColors.blue),
        ),
        title: Text(bot['name']?.toString() ?? 'Bot'),
        subtitle: Text(
          '${bot['repository'] ?? 'Repozytorium niedostępne'} · $activeStages aktywnych etapów',
          style: const TextStyle(color: AppColors.muted),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

class _AccountRepositoryGroup extends StatelessWidget {
  const _AccountRepositoryGroup({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});

  final Map<String, dynamic> task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text('${task['number'] ?? ''}. ${task['title'] ?? 'Etap'}'),
          subtitle: Text(
            '${task['botName'] ?? 'Bot'} · ${task['repository'] ?? 'Repozytorium'} · ${_statusLabel(task['status'])}',
            style: const TextStyle(color: AppColors.muted),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      );
}

class _PullRequestCard extends StatelessWidget {
  const _PullRequestCard({
    required this.request,
    required this.onOpen,
    required this.onGitHub,
  });

  final Map<String, dynamic> request;
  final VoidCallback onOpen;
  final VoidCallback onGitHub;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(
            '#${request['number']} · ${request['title'] ?? 'Pull request'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${request['repository']} · ${request['botName']} · ${request['status'] ?? 'nieznany status'} · CI: ${request['ciStatus'] ?? 'brak danych'}',
            style: const TextStyle(color: AppColors.muted),
          ),
          onTap: onOpen,
          trailing: PopupMenuButton<String>(
            tooltip: 'Otwórz pull request',
            onSelected: (_) => onGitHub(),
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'github', child: Text('Otwórz na GitHub')),
            ],
          ),
        ),
      );
}

class _ReviewStageCard extends StatelessWidget {
  const _ReviewStageCard({
    required this.stage,
    required this.onOpenBot,
    required this.onOpenEditor,
  });

  final Map<String, dynamic> stage;
  final VoidCallback onOpenBot;
  final VoidCallback onOpenEditor;

  @override
  Widget build(BuildContext context) {
    final requests = _records(stage['pullRequests']);
    final status = stage['status']?.toString() ?? 'nieznany';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(stage['title']?.toString() ?? 'Etap', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              '${stage['botName']} · ${stage['repository']} · ${_statusLabel(status)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (requests.isEmpty)
              const Text(
                'Nie ma powiązanego PR ani zweryfikowanego statusu CI.',
                style: TextStyle(color: AppColors.amber, fontSize: 12),
              )
            else
              for (final request in requests)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'PR #${request['number']} · ${request['headBranch'] ?? 'gałąź nieznana'} → ${request['baseBranch'] ?? 'gałąź bazowa'} · CI: ${request['ciStatus'] ?? 'brak danych'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
            const SizedBox(height: 7),
            const Text(
              'Brak zarejestrowanego deploymentu preview i testów manualnych przypiętych do commit SHA.',
              style: TextStyle(color: AppColors.amber, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Tooltip(
                  message: 'Preview CI/CD nie jest skonfigurowane dla tego etapu.',
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.play_circle_outline_rounded),
                    label: Text('Testuj aplikację'),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: kIsWeb ? onOpenEditor : null,
                  icon: const Icon(Icons.code_rounded),
                  label: const Text('Otwórz kod w VS Code'),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenBot,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Szczegóły bota'),
                ),
                Tooltip(
                  message: 'Wymagane są zielone CI, aktualne preview i testy manualne.',
                  child: FilledButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.check_rounded),
                    label: Text('Zatwierdź etap'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openEditor(BuildContext context, WidgetRef ref) async {
  try {
    await openCodeEditor(ref.read(apiClientProvider));
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }
}

Future<void> _openGitHubUrl(BuildContext context, Object? value) async {
  final uri = Uri.tryParse(value?.toString() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pull request nie ma prawidłowego adresu GitHub.')),
    );
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Nie udało się otworzyć pull requesta.')),
    );
  }
}

String _statusLabel(Object? value) => switch (value?.toString()) {
      'PENDING' => 'Oczekuje',
      'RUNNING' => 'W trakcie',
      'TESTING' => 'Testowanie',
      'WAITING_APPROVAL' => 'Do review',
      'APPROVED' => 'Zatwierdzony',
      'CHANGES_REQUESTED' => 'Do poprawek',
      'FAILED' => 'Błąd',
      'PAUSED' => 'Wstrzymany',
      'CANCELLED' => 'Anulowany',
      'OPEN' => 'Otwarty',
      'CLOSED' => 'Zamknięty',
      'MERGED' => 'Scalony',
      _ => value?.toString() ?? 'Nieznany status',
    };

List<Map<String, dynamic>> _records(Object? value) => value is List
    ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
    : const [];
