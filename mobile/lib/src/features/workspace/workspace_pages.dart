import 'package:file_picker/file_picker.dart';
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

class TeamsPage extends ConsumerStatefulWidget {
  const TeamsPage({super.key});

  @override
  ConsumerState<TeamsPage> createState() => _TeamsPageState();
}

class _TeamsPageState extends ConsumerState<TeamsPage> {
  bool _saving = false;

  Future<void> _createTeam() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final value = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nowy zespół AI'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nazwa zespołu'),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Opis'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'name': name.text.trim(),
                      'description': description.text.trim(),
                    }),
              child: const Text('Utwórz'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    if (value == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .createTeam(name: value['name']!, description: value['description']!);
      ref.invalidate(teamsProvider);
      _showMessage('Zespół został zapisany.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setBot({
    required String teamId,
    required String botId,
    required bool assigned,
  }) async {
    try {
      await ref
          .read(apiClientProvider)
          .setTeamBot(teamId: teamId, botId: botId, assigned: assigned);
      ref.invalidate(teamsProvider);
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.coral : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(teamsProvider);
    final bots = ref.watch(botsProvider);
    return _PageFrame(
      title: 'Zespoły AI',
      subtitle: 'Twórz trwałe zespoły i przypisuj do nich własne boty.',
      action: FilledButton.icon(
        onPressed: _saving ? null : _createTeam,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nowy zespół'),
      ),
      children: [
        if (_saving) const LinearProgressIndicator(),
        teams.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(teamsProvider),
          ),
          data: (items) => items.isEmpty
              ? const _InformationCard(
                  icon: Icons.groups_outlined,
                  title: 'Nie ma jeszcze zespołów',
                  body: 'Utwórz zespół, a następnie przypisz do niego zapisane boty.',
                )
              : bots.when(
                  loading: () => const _LoadingCard(),
                  error: (error, stack) => _ErrorCard(
                    message: error.toString(),
                    onRetry: () => ref.invalidate(botsProvider),
                  ),
                  data: (botItems) => Column(
                    children: [
                      for (final team in items)
                        _TeamCard(
                          team: team,
                          bots: botItems,
                          onToggle: (botId, assigned) => _setBot(
                            teamId: team['id'].toString(),
                            botId: botId,
                            assigned: assigned,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({
    required this.team,
    required this.bots,
    required this.onToggle,
  });

  final Map<String, dynamic> team;
  final List<Map<String, dynamic>> bots;
  final Future<void> Function(String botId, bool assigned) onToggle;

  @override
  Widget build(BuildContext context) {
    final members = _records(team['bots'])
        .map((membership) => membership['bot'])
        .whereType<Map>()
        .map((bot) => Map<String, dynamic>.from(bot))
        .toList();
    final assignedIds = members.map((bot) => bot['id'].toString()).toSet();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.groups_outlined, color: AppColors.blue),
        title: Text(team['name']?.toString() ?? 'Zespół'),
        subtitle: Text('${members.length} botów przypisanych'),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if ((team['description']?.toString() ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(team['description'].toString()),
              ),
            ),
          if (bots.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Utwórz bota w sekcji Boty, aby dodać go do zespołu.',
                style: TextStyle(color: AppColors.muted),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bot in bots)
                  FilterChip(
                    label: Text('${bot['name']} · ${bot['repository']}'),
                    selected: assignedIds.contains(bot['id'].toString()),
                    onSelected: (selected) =>
                        onToggle(bot['id'].toString(), selected),
                  ),
              ],
            ),
        ],
      ),
    );
  }
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
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
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
                  _RepositoriesForAccount(account: account, query: _query),
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
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                        trailing: repository['canPush'] == true
                            ? const Icon(
                                Icons.edit_outlined,
                                color: AppColors.mint,
                              )
                            : const Icon(
                                Icons.visibility_outlined,
                                color: AppColors.muted,
                              ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}

String _projectStageLabel(String stage) => switch (stage) {
  'DISCOVERY' => 'rozpoznanie',
  'PLANNING' => 'planowanie',
  'IMPLEMENTATION' => 'realizacja',
  'BLOCKED' => 'zablokowany',
  'VALIDATION' => 'walidacja',
  _ => stage,
};

class ProjectsPage extends ConsumerStatefulWidget {
  const ProjectsPage({super.key});

  @override
  ConsumerState<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends ConsumerState<ProjectsPage> {
  bool _saving = false;
  String? _scanningProjectId;

  Future<void> _createProject() async {
    final name = TextEditingController();
    final description = TextEditingController();
    final repository = TextEditingController();
    final details = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Nowy projekt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nazwa projektu',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Opis'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: repository,
                  decoration: const InputDecoration(
                    labelText: 'Repozytorium (opcjonalnie)',
                    hintText: 'właściciel/repo',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, {
                      'name': name.text.trim(),
                      'description': description.text.trim(),
                      'repository': repository.text.trim(),
                    }),
              child: const Text('Utwórz projekt'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    description.dispose();
    repository.dispose();
    if (details == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .createProject(
            name: details['name']!,
            description: details['description']!,
            repository: details['repository'],
          );
      ref.invalidate(projectsProvider);
      _showMessage('Projekt zapisany.');
    } on Object catch (error) {
      _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadPdf(String projectId) async {
    final List<PlatformFile> selection;
    try {
      selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          'Nie udało się otworzyć selektora plików: $error',
          error: true,
        );
      }
      return;
    }
    if (selection.isEmpty || !mounted) return;
    final file = selection.single;
    late final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on Object catch (error) {
      _showMessage(
        'Nie udało się odczytać wybranego pliku: $error',
        error: true,
      );
      return;
    }
    if (!mounted) return;
    if (bytes.isEmpty) {
      _showMessage('Nie udało się odczytać wybranego pliku.', error: true);
      return;
    }
    if (bytes.length > 10 * 1024 * 1024) {
      _showMessage('PDF może mieć maksymalnie 10 MB.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .uploadProjectPdf(
            projectId: projectId,
            filename: file.name,
            bytes: bytes,
          );
      ref.invalidate(projectsProvider);
      _showMessage(
        'PDF zapisany i odczytany. Kolejne przesłanie tej samej nazwy utworzy nową wersję.',
      );
    } on Object catch (error) {
      _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scanProject(Map<String, dynamic> project) async {
    final repository = project['repository']?.toString();
    if (repository == null || repository.isEmpty) {
      _showMessage(
        'Dodaj repozytorium GitHub do projektu, aby go zeskanować.',
        error: true,
      );
      return;
    }

    try {
      final session = await ref.read(sessionDataProvider.future);
      if (!mounted) return;
      final accounts = _records(session['githubAccounts'])
          .where((account) => account['status'] == 'ACTIVE')
          .toList();
      if (accounts.isEmpty) {
        _showMessage(
          'Połącz aktywne konto GitHub przed skanowaniem.',
          error: true,
        );
        return;
      }

      String? accountId;
      if (accounts.length == 1) {
        accountId = accounts.single['id']?.toString();
      } else {
        String? selectedId = accounts.first['id']?.toString();
        accountId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Wybierz konto GitHub'),
              content: DropdownButtonFormField<String>(
                key: ValueKey(selectedId),
                initialValue: selectedId,
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account['id']?.toString(),
                      child: Text('@${account['login'] ?? 'GitHub'}'),
                    ),
                ],
                onChanged: (value) => setDialogState(() => selectedId = value),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Anuluj'),
                ),
                FilledButton(
                  onPressed: selectedId == null
                      ? null
                      : () => Navigator.pop(dialogContext, selectedId),
                  child: const Text('Skanuj'),
                ),
              ],
            ),
          ),
        );
      }
      if (accountId == null || !mounted) return;

      setState(() => _scanningProjectId = project['id'].toString());
      final response = await ref
          .read(apiClientProvider)
          .scanProject(
            projectId: project['id'].toString(),
            githubAccountId: accountId,
          );
      if (!mounted) return;
      ref.invalidate(projectsProvider);
      final scan = response['scan'];
      final stage = scan is Map ? scan['lifecycleStage']?.toString() : null;
      _showMessage(
        stage == null
            ? 'Skan projektu zakończony.'
            : 'Skan zakończony. Wykryty etap pracy: ${_projectStageLabel(stage)}.',
      );
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _scanningProjectId = null);
    }
  }

  Future<void> _setProjectRepository(Map<String, dynamic> project) async {
    final repository = TextEditingController(
      text: project['repository']?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Połącz repozytorium'),
        content: TextField(
          controller: repository,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Repozytorium GitHub',
            hintText: 'właściciel/repo',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, repository.text.trim()),
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );
    repository.dispose();
    if (value == null || !mounted) return;
    if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(value)) {
      _showMessage(
        'Podaj repozytorium w formacie właściciel/repo.',
        error: true,
      );
      return;
    }

    try {
      await ref
          .read(apiClientProvider)
          .setProjectRepository(
            projectId: project['id'].toString(),
            repository: value,
          );
      ref.invalidate(projectsProvider);
      _showMessage('Repozytorium projektu zapisane.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _showDocumentText({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  }) async {
    try {
      final response = await ref
          .read(apiClientProvider)
          .getProjectDocumentVersion(
            documentId: document['id'].toString(),
            version: int.parse(version['version'].toString()),
          );
      final data = response['document'];
      if (data is! Map || !mounted) return;
      final text = data['extractedText']?.toString() ?? '';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${document['filename']} · wersja ${version['version']}'),
          content: SizedBox(
            width: 720,
            child: SingleChildScrollView(child: SelectableText(text)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Zamknij'),
            ),
          ],
        ),
      );
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _downloadDocument({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  }) async {
    try {
      final bytes = await ref
          .read(apiClientProvider)
          .downloadProjectDocument(
            documentId: document['id'].toString(),
            version: int.parse(version['version'].toString()),
          );
      final uri = await FilePicker.saveFile(
        fileName: document['filename'].toString(),
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (mounted && uri != null) _showMessage('PDF pobrany.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usuń dokument?'),
        content: Text(
          'Dokument ${document['filename']} zostanie ukryty. Zaszyfrowane wersje pozostaną w historii retencji.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(apiClientProvider)
          .deleteProjectDocument(document['id'].toString());
      ref.invalidate(projectsProvider);
      _showMessage('Dokument ukryty. Wersje pozostają zachowane.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.coral : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    return _PageFrame(
      title: 'Projekty i PDF',
      subtitle: 'Śledź etap pracy z repozytorium i przekazuj botom aktualny kontekst; dokumenty PDF są wersjonowane i odczytywane tekstowo.',
      action: FilledButton.icon(
        onPressed: _saving ? null : _createProject,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nowy projekt'),
      ),
      children: [
        if (_saving) const LinearProgressIndicator(),
        projects.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(projectsProvider),
          ),
          data: (items) => items.isEmpty
              ? const _InformationCard(
                  icon: Icons.folder_open_outlined,
                  title: 'Nie ma jeszcze projektów',
                  body: 'Utwórz projekt, a następnie dodaj dokument PDF. Pliki są szyfrowane na serwerze, a odczyt tekstu nie uruchamia poleceń z dokumentu.',
                )
              : Column(
                  children: [
                    for (final project in items)
                      _ProjectCard(
                        project: project,
                        onUpload: () => _uploadPdf(project['id'].toString()),
                        onScan: _scanProject,
                        onSetRepository: _setProjectRepository,
                        scanning:
                            _scanningProjectId == project['id'].toString(),
                        onRead: _showDocumentText,
                        onDownload: _downloadDocument,
                        onDelete: _deleteDocument,
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onUpload,
    required this.onScan,
    required this.onSetRepository,
    required this.scanning,
    required this.onRead,
    required this.onDownload,
    required this.onDelete,
  });

  final Map<String, dynamic> project;
  final VoidCallback onUpload;
  final Future<void> Function(Map<String, dynamic> project) onScan;
  final Future<void> Function(Map<String, dynamic> project) onSetRepository;
  final bool scanning;
  final Future<void> Function({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  })
  onRead;
  final Future<void> Function({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  })
  onDownload;
  final Future<void> Function(Map<String, dynamic> document) onDelete;

  @override
  Widget build(BuildContext context) {
    final documents = _records(project['documents']);
    final scans = _records(project['scans']);
    final latestScan = scans.isEmpty ? null : scans.first;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: const Icon(Icons.folder_open_outlined, color: AppColors.blue),
        title: Text(project['name']?.toString() ?? 'Projekt'),
        subtitle: Text(
          [
            if (project['repository'] is String) project['repository'],
            '${documents.length} dokumentów',
          ].join(' · '),
          style: const TextStyle(color: AppColors.muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          if ((project['description']?.toString() ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(project['description'].toString()),
              ),
            ),
          if (latestScan != null)
            Card(
              color: AppColors.panelRaised,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Etap projektu: ${_projectStageLabel(latestScan['lifecycleStage']?.toString() ?? '')}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      latestScan['summary']?.toString() ??
                          'Brak podsumowania skanu.',
                      style: const TextStyle(
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                    if (latestScan['treeTruncated'] == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'GitHub zwrócił niepełne drzewo plików; wynik może pomijać część repozytorium.',
                          style: TextStyle(color: AppColors.amber),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: scanning ? null : () => onScan(project),
                  icon: scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.manage_search_rounded),
                  label: Text(
                    scanning
                        ? 'Skanuję repozytorium…'
                        : 'Skanuj postęp projektu',
                  ),
                ),
                if ((project['repository']?.toString() ?? '').isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => onSetRepository(project),
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Połącz repozytorium'),
                  ),
                OutlinedButton.icon(
                  onPressed: onUpload,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Dodaj PDF (do 10 MB)'),
                ),
              ],
            ),
          ),
          if (documents.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Projekt nie ma jeszcze dokumentów.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          for (final document in documents)
            _ProjectDocument(
              document: document,
              onRead: onRead,
              onDownload: onDownload,
              onDelete: onDelete,
            ),
        ],
      ),
    );
  }
}

class _ProjectDocument extends StatelessWidget {
  const _ProjectDocument({
    required this.document,
    required this.onRead,
    required this.onDownload,
    required this.onDelete,
  });

  final Map<String, dynamic> document;
  final Future<void> Function({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  })
  onRead;
  final Future<void> Function({
    required Map<String, dynamic> document,
    required Map<String, dynamic> version,
  })
  onDownload;
  final Future<void> Function(Map<String, dynamic> document) onDelete;

  @override
  Widget build(BuildContext context) {
    final versions = _records(document['versions']);
    return ExpansionTile(
      leading: const Icon(
        Icons.picture_as_pdf_outlined,
        color: AppColors.amber,
      ),
      title: Text(document['filename']?.toString() ?? 'PDF'),
      subtitle: Text(
        '${versions.length} wersji · bieżąca ${document['currentVersion'] ?? '-'}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Opcje dokumentu',
        onSelected: (action) {
          if (action == 'delete') onDelete(document);
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'delete', child: Text('Usuń dokument')),
        ],
      ),
      children: [
        for (final version in versions)
          ListTile(
            dense: true,
            title: Text(
              'Wersja ${version['version']} · ${version['pageCount']} stron',
            ),
            subtitle: Text(
              '${_formatFileSize(version['sizeBytes'])} · SHA-256 ${version['contentHash']}',
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Odczytaj tekst',
                  onPressed: () => onRead(document: document, version: version),
                  icon: const Icon(Icons.article_outlined),
                ),
                IconButton(
                  tooltip: 'Pobierz PDF',
                  onPressed: () =>
                      onDownload(document: document, version: version),
                  icon: const Icon(Icons.download_outlined),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _formatFileSize(Object? rawSize) {
  final size = rawSize is num ? rawSize.toInt() : 0;
  if (size < 1024) return '$size B';
  if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
  return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
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
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
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
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(
                    value: 'ALL',
                    child: Text(
                      'Wszystkie statusy',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(value: 'PENDING', child: Text('Oczekujące')),
                  DropdownMenuItem(value: 'RUNNING', child: Text('W trakcie')),
                  DropdownMenuItem(
                    value: 'WAITING_APPROVAL',
                    child: Text('Do review'),
                  ),
                  DropdownMenuItem(
                    value: 'APPROVED',
                    child: Text('Zatwierdzone'),
                  ),
                  DropdownMenuItem(
                    value: 'CHANGES_REQUESTED',
                    child: Text('Do poprawek'),
                  ),
                  DropdownMenuItem(value: 'FAILED', child: Text('Błąd')),
                ],
                onChanged: (value) => setState(() => _status = value ?? 'ALL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const _ProjectTaskBoard(),
        const SizedBox(height: 20),
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
                if ((_status == 'ALL' || status == _status) &&
                    searchable.contains(_query)) {
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

class _ProjectTaskBoard extends ConsumerStatefulWidget {
  const _ProjectTaskBoard();

  @override
  ConsumerState<_ProjectTaskBoard> createState() => _ProjectTaskBoardState();
}

class _ProjectTaskBoardState extends ConsumerState<_ProjectTaskBoard> {
  bool _saving = false;

  Future<void> _createTask() async {
    final List<Map<String, dynamic>> projects;
    final List<Map<String, dynamic>> tasks;
    try {
      projects = await ref.read(projectsProvider.future);
      tasks = await ref.read(projectTasksProvider.future);
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
      return;
    }
    if (!mounted) return;
    if (projects.isEmpty) {
      _showMessage('Najpierw utwórz projekt, do którego przypiszesz zadania.');
      return;
    }

    final title = TextEditingController();
    final description = TextEditingController();
    var projectId = projects.first['id'].toString();
    final dependencyIds = <String>{};
    final values = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final projectTasks = tasks
              .where((task) => task['projectId'] == projectId)
              .toList();
          dependencyIds.removeWhere(
            (id) => !projectTasks.any((task) => task['id'] == id),
          );
          return AlertDialog(
            title: const Text('Nowe zadanie projektu'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(projectId),
                      initialValue: projectId,
                      decoration: const InputDecoration(labelText: 'Projekt'),
                      items: [
                        for (final project in projects)
                          DropdownMenuItem(
                            value: project['id'].toString(),
                            child: Text(project['name'].toString()),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() {
                          projectId = value;
                          dependencyIds.clear();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: title,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: 'Zadanie'),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Opis'),
                    ),
                    if (projectTasks.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Zależne od (muszą być ukończone wcześniej)',
                        ),
                      ),
                      for (final task in projectTasks)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: dependencyIds.contains(task['id'].toString()),
                          title: Text(task['title'].toString()),
                          subtitle: Text(
                            _projectTaskStatusLabel(
                              task['status']?.toString() ?? 'TODO',
                            ),
                          ),
                          onChanged: (selected) => setDialogState(() {
                            final id = task['id'].toString();
                            if (selected == true) {
                              dependencyIds.add(id);
                            } else {
                              dependencyIds.remove(id);
                            }
                          }),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: title.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, {
                        'projectId': projectId,
                        'title': title.text.trim(),
                        'description': description.text.trim(),
                        'dependencyIds': dependencyIds.toList(),
                      }),
                child: const Text('Utwórz zadanie'),
              ),
            ],
          );
        },
      ),
    );
    title.dispose();
    description.dispose();
    if (values == null || !mounted) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .createProjectTask(
            projectId: values['projectId'] as String,
            title: values['title'] as String,
            description: values['description'] as String,
            dependencyIds: (values['dependencyIds'] as List).cast<String>(),
          );
      ref.invalidate(projectTasksProvider);
      _showMessage('Zadanie i zależności zapisane.');
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeStatus(String taskId, String status) async {
    try {
      await ref
          .read(apiClientProvider)
          .updateProjectTask(taskId: taskId, status: status);
      ref.invalidate(projectTasksProvider);
    } on Object catch (error) {
      if (mounted) _showMessage(error.toString(), error: true);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.coral : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(projectTasksProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Zadania projektu i zależności',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _saving ? null : _createTask,
                  icon: const Icon(Icons.add_task_rounded),
                  label: const Text('Dodaj zadanie'),
                ),
              ],
            ),
            if (_saving) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            tasks.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stack) => _ErrorCard(
                message: error.toString(),
                onRetry: () => ref.invalidate(projectTasksProvider),
              ),
              data: (items) => items.isEmpty
                  ? const Text(
                      'Nie ma jeszcze zadań projektowych.',
                      style: TextStyle(color: AppColors.muted),
                    )
                  : Column(
                      children: [
                        for (final task in items)
                          _ProjectTaskRow(
                            task: task,
                            onStatusChanged: (status) =>
                                _changeStatus(task['id'].toString(), status),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _projectTaskStatusLabel(String status) => switch (status) {
  'TODO' => 'Do zrobienia',
  'IN_PROGRESS' => 'W toku',
  'BLOCKED' => 'Zablokowane',
  'COMPLETED' => 'Ukończone',
  _ => status,
};

class _ProjectTaskRow extends StatelessWidget {
  const _ProjectTaskRow({required this.task, required this.onStatusChanged});

  final Map<String, dynamic> task;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final status = task['status']?.toString() ?? 'TODO';
    final prerequisites = _records(task['prerequisites'])
        .map((item) => item['dependsOn'])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final unmet = prerequisites
        .where((item) => item['status'] != 'COMPLETED')
        .toList();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(task['title']?.toString() ?? 'Zadanie'),
      subtitle: Text(
        '${task['project'] is Map ? (task['project'] as Map)['name'] : 'Projekt'}'
        '${prerequisites.isEmpty ? '' : ' · zależności: ${prerequisites.map((item) => item['title']).join(', ')}'}'
        '${unmet.isEmpty ? '' : ' · oczekuje na ukończenie zależności'}',
        style: const TextStyle(color: AppColors.muted),
      ),
      trailing: DropdownButton<String>(
        value: status,
        items: const [
          DropdownMenuItem(value: 'TODO', child: Text('Do zrobienia')),
          DropdownMenuItem(value: 'IN_PROGRESS', child: Text('W toku')),
          DropdownMenuItem(value: 'BLOCKED', child: Text('Zablokowane')),
          DropdownMenuItem(value: 'COMPLETED', child: Text('Ukończone')),
        ],
        onChanged: (value) {
          if (value != null && value != status) onStatusChanged(value);
        },
      ),
    );
  }
}

class CollaborationPage extends ConsumerStatefulWidget {
  const CollaborationPage({super.key});

  @override
  ConsumerState<CollaborationPage> createState() => _CollaborationPageState();
}

class _CollaborationPageState extends ConsumerState<CollaborationPage> {
  final _message = TextEditingController();
  final _helpTitle = TextEditingController();
  final _helpDescription = TextEditingController();
  final _checkpointTitle = TextEditingController();
  final _checkpointNotes = TextEditingController();
  final _checkpointCommit = TextEditingController();
  String? _projectId;
  String _checkpointStage = 'IMPLEMENTATION';

  @override
  void dispose() {
    _message.dispose();
    _helpTitle.dispose();
    _helpDescription.dispose();
    _checkpointTitle.dispose();
    _checkpointNotes.dispose();
    _checkpointCommit.dispose();
    super.dispose();
  }

  Future<bool> _save(
    Future<Map<String, dynamic>> Function() action,
    String successMessage, {
    required String projectId,
  }) async {
    try {
      await action();
      if (!mounted) return false;
      ref.invalidate(projectCollaborationProvider(projectId));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
      return true;
    } on Object catch (error) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          backgroundColor: AppColors.coral,
        ),
      );
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    return _PageFrame(
      title: 'Współpraca',
      subtitle: 'Trwały dziennik projektu, prośby o pomoc i ręcznie zapisane checkpointy.',
      children: [
        projects.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(projectsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const _InformationCard(
                icon: Icons.forum_outlined,
                title: 'Najpierw utwórz projekt',
                body: 'Dziennik współpracy, prośby o pomoc i checkpointy są przypisane do projektu.',
              );
            }
            final projectIds = items
                .map((project) => project['id'].toString())
                .toSet();
            final projectId = projectIds.contains(_projectId)
                ? _projectId!
                : items.first['id'].toString();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(projectId),
                  initialValue: projectId,
                  decoration: const InputDecoration(labelText: 'Projekt'),
                  items: [
                    for (final project in items)
                      DropdownMenuItem(
                        value: project['id'].toString(),
                        child: Text(project['name'].toString()),
                      ),
                  ],
                  onChanged: (value) => setState(() => _projectId = value),
                ),
                const SizedBox(height: 16),
                _collaborationContent(projectId),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _collaborationContent(String projectId) {
    final collaboration = ref.watch(projectCollaborationProvider(projectId));
    return collaboration.when(
      loading: () => const _LoadingCard(),
      error: (error, stack) => _ErrorCard(
        message: error.toString(),
        onRetry: () => ref.invalidate(projectCollaborationProvider(projectId)),
      ),
      data: (data) {
        final messages = _records(data['messages']);
        final helpRequests = _records(data['helpRequests']);
        final checkpoints = _records(data['checkpoints']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CollaborationSection(
              title: 'Dziennik projektu',
              children: [
                TextField(
                  controller: _message,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Wiadomość',
                    hintText: 'Notatka widoczna w historii projektu',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _message.text.trim().isEmpty
                        ? null
                        : () async {
                            final content = _message.text.trim();
                            final saved = await _save(
                              () => ref
                                  .read(apiClientProvider)
                                  .createProjectMessage(
                                    projectId: projectId,
                                    content: content,
                                  ),
                              'Wiadomość została zapisana.',
                              projectId: projectId,
                            );
                            if (saved && mounted) _message.clear();
                          },
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Dodaj wpis'),
                  ),
                ),
                if (messages.isEmpty)
                  const _InlineEmpty('Brak wpisów w dzienniku.')
                else
                  for (final message in messages)
                    _CollaborationEntry(
                      title:
                          (message['author'] as Map?)?['displayName']
                              ?.toString() ??
                          'Użytkownik',
                      body: message['content']?.toString() ?? '',
                      metadata: _entryTime(message['createdAt']),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            _CollaborationSection(
              title: 'Prośby o pomoc',
              children: [
                TextField(
                  controller: _helpTitle,
                  decoration: const InputDecoration(labelText: 'Temat'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _helpDescription,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Opis'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _helpTitle.text.trim().isEmpty
                        ? null
                        : () async {
                            final title = _helpTitle.text.trim();
                            final description = _helpDescription.text.trim();
                            final saved = await _save(
                              () => ref
                                  .read(apiClientProvider)
                                  .createProjectHelpRequest(
                                    projectId: projectId,
                                    title: title,
                                    description: description,
                                  ),
                              'Prośba o pomoc została zapisana.',
                              projectId: projectId,
                            );
                            if (saved && mounted) {
                              _helpTitle.clear();
                              _helpDescription.clear();
                            }
                          },
                    icon: const Icon(Icons.help_outline_rounded),
                    label: const Text('Utwórz prośbę'),
                  ),
                ),
                if (helpRequests.isEmpty)
                  const _InlineEmpty('Brak próśb o pomoc.')
                else
                  for (final request in helpRequests)
                    _CollaborationEntry(
                      title: request['title']?.toString() ?? 'Prośba o pomoc',
                      body: request['description']?.toString() ?? '',
                      metadata:
                          '${request['status'] == 'RESOLVED' ? 'Rozwiązana' : 'Otwarta'} · ${_entryTime(request['createdAt'])}',
                      action: request['status'] == 'RESOLVED'
                          ? null
                          : TextButton(
                              onPressed: () => _save(
                                () => ref
                                    .read(apiClientProvider)
                                    .resolveProjectHelpRequest(
                                      projectId: projectId,
                                      helpRequestId: request['id'].toString(),
                                    ),
                                'Prośba została oznaczona jako rozwiązana.',
                                projectId: projectId,
                              ),
                              child: const Text('Rozwiąż'),
                            ),
                    ),
              ],
            ),
            const SizedBox(height: 14),
            _CollaborationSection(
              title: 'Ręczne checkpointy',
              children: [
                const Text(
                  'To notatki użytkownika. Nie zapisują stanu procesu agenta, '
                  'nie weryfikują SHA i nie wznawiają zadania.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _checkpointTitle,
                  decoration: const InputDecoration(labelText: 'Tytuł'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _checkpointNotes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notatki'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _checkpointCommit,
                  decoration: const InputDecoration(
                    labelText: 'Commit SHA (opcjonalnie)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _checkpointStage,
                  decoration: const InputDecoration(
                    labelText: 'Szacowany etap projektu',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'DISCOVERY',
                      child: Text('Rozpoznanie'),
                    ),
                    DropdownMenuItem(
                      value: 'PLANNING',
                      child: Text('Planowanie'),
                    ),
                    DropdownMenuItem(
                      value: 'IMPLEMENTATION',
                      child: Text('Implementacja'),
                    ),
                    DropdownMenuItem(
                      value: 'BLOCKED',
                      child: Text('Zablokowany'),
                    ),
                    DropdownMenuItem(
                      value: 'VALIDATION',
                      child: Text('Walidacja'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _checkpointStage = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _checkpointTitle.text.trim().isEmpty
                        ? null
                        : () async {
                            final title = _checkpointTitle.text.trim();
                            final notes = _checkpointNotes.text.trim();
                            final sha = _checkpointCommit.text.trim();
                            final saved = await _save(
                              () => ref
                                  .read(apiClientProvider)
                                  .createProjectCheckpoint(
                                    projectId: projectId,
                                    title: title,
                                    notes: notes,
                                    commitSha: sha.isEmpty ? null : sha,
                                    progressStage: _checkpointStage,
                                  ),
                              'Checkpoint został zapisany jako notatka ręczna.',
                              projectId: projectId,
                            );
                            if (saved && mounted) {
                              _checkpointTitle.clear();
                              _checkpointNotes.clear();
                              _checkpointCommit.clear();
                            }
                          },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Zapisz checkpoint'),
                  ),
                ),
                if (checkpoints.isEmpty)
                  const _InlineEmpty('Brak zapisanych checkpointów.')
                else
                  for (final checkpoint in checkpoints)
                    _CollaborationEntry(
                      title: checkpoint['title']?.toString() ?? 'Checkpoint',
                      body: checkpoint['notes']?.toString() ?? '',
                      metadata:
                          '${_progressStageLabel(checkpoint['progressStage']?.toString())}'
                          '${checkpoint['commitSha'] == null ? '' : ' · SHA ${checkpoint['commitSha']}'}'
                          ' · ${_entryTime(checkpoint['createdAt'])}',
                    ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _CollaborationSection extends StatelessWidget {
  const _CollaborationSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _CollaborationEntry extends StatelessWidget {
  const _CollaborationEntry({
    required this.title,
    required this.body,
    required this.metadata,
    this.action,
  });

  final String title;
  final String body;
  final String metadata;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(
      [body, metadata].where((value) => value.isNotEmpty).join('\n'),
    ),
    trailing: action,
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(message, style: const TextStyle(color: AppColors.muted)),
  );
}

String _entryTime(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return 'czas nieznany';
  final local = date.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String _progressStageLabel(String? stage) => switch (stage) {
  'DISCOVERY' => 'Rozpoznanie',
  'PLANNING' => 'Planowanie',
  'IMPLEMENTATION' => 'Implementacja',
  'BLOCKED' => 'Zablokowany',
  'VALIDATION' => 'Walidacja',
  _ => 'Etap nieokreślony',
};

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
        title: kIsWeb
            ? 'Edytor działa w osobnym workspace'
            : 'Edytor jest dostępny w przeglądarce',
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
          title: 'Zatwierdzenie wymaga dowodów zweryfikowanych przez serwer',
          body: 'Serwer odpyta GitHub o zielone CI dla aktualnego commita PR i sprawdzi zapisany test manualny przypięty do tego samego SHA. Preview nie jest jeszcze udostępniane ani wymuszane. Zatwierdzasz w szczegółach bota.',
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

class SchedulePage extends ConsumerStatefulWidget {
  const SchedulePage({super.key});

  @override
  ConsumerState<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends ConsumerState<SchedulePage> {
  static const _days = ['Nd', 'Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So'];
  final _timezone = TextEditingController();
  final _start = TextEditingController(text: '09:00');
  final _end = TextEditingController(text: '17:00');
  final Set<int> _selected = {1, 2, 3, 4, 5};
  bool _enabled = false;
  bool _loaded = false;

  @override
  void dispose() {
    _timezone.dispose();
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _load(Map<String, dynamic> schedule) {
    if (_loaded) return;
    _loaded = true;
    _enabled = schedule['enabled'] == true;
    _timezone.text = schedule['timezone']?.toString() ?? 'UTC';
    final windows = (schedule['windows'] as List? ?? const []).whereType<Map>();
    if (windows.isNotEmpty) {
      _selected
        ..clear()
        ..addAll(windows.map((window) => window['day'] as int));
      _start.text = windows.first['start'].toString();
      _end.text = windows.first['end'].toString();
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(apiClientProvider).request(
        '/schedule',
        method: 'POST',
        data: {
          'enabled': _enabled,
          'timezone': _timezone.text.trim(),
          'windows': [
            for (final day in _selected.toList()..sort())
              {'day': day, 'start': _start.text.trim(), 'end': _end.text.trim()},
          ],
        },
      );
      ref.invalidate(scheduleProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Harmonogram zapisany.')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: AppColors.coral),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider);
    return _PageFrame(
      title: 'Harmonogram pracy',
      subtitle: 'Okna pracy, w których serwer pozwala uruchamiać etapy.',
      children: [
        schedule.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(scheduleProvider),
          ),
          data: (value) {
            _load(value);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Wymuszaj okna pracy'),
                      subtitle: const Text(
                        'Start etapu poza oknem zwróci błąd OUTSIDE_WORK_WINDOW. Nie zatrzymuje już uruchomionych zadań.',
                      ),
                      value: _enabled,
                      onChanged: (value) => setState(() => _enabled = value),
                    ),
                    TextField(
                      controller: _timezone,
                      decoration: const InputDecoration(labelText: 'Strefa czasowa (IANA)'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (var day = 0; day < 7; day++)
                          FilterChip(
                            label: Text(_days[day]),
                            selected: _selected.contains(day),
                            onSelected: (on) => setState(() {
                              on ? _selected.add(day) : _selected.remove(day);
                            }),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _start,
                            decoration: const InputDecoration(labelText: 'Od (HH:MM)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _end,
                            decoration: const InputDecoration(labelText: 'Do (HH:MM)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FilledButton(onPressed: _save, child: const Text('Zapisz harmonogram')),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class CostsPage extends ConsumerStatefulWidget {
  const CostsPage({super.key});

  @override
  ConsumerState<CostsPage> createState() => _CostsPageState();
}

class _CostsPageState extends ConsumerState<CostsPage> {
  final _limit = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _csv = TextEditingController();
  bool _enforce = false;
  bool _loaded = false;

  @override
  void dispose() {
    _limit.dispose();
    _currency.dispose();
    _csv.dispose();
    super.dispose();
  }

  String _money(int minor, String currency) =>
      '${(minor / 100).toStringAsFixed(2)} $currency';

  Future<void> _run(Future<void> Function() action, String message) async {
    try {
      await action();
      ref.invalidate(costsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString()), backgroundColor: AppColors.coral),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final costs = ref.watch(costsProvider);
    return _PageFrame(
      title: 'Koszty AI',
      subtitle: 'Import CSV, limit zużycia i koszty stałe. Dane pochodzą wyłącznie z Twoich importów.',
      children: [
        const _InformationCard(
          icon: Icons.payments_outlined,
          title: 'Brak automatycznego źródła rozliczeń',
          body: 'GitHub Agent Tasks nie udostępnia zużycia ani cen. Pokazujemy tylko wpisy zaimportowane z CSV; zużycie i subskrypcje są liczone osobno, a limit dotyczy tylko zużycia.',
          warning: true,
        ),
        costs.when(
          loading: () => const _LoadingCard(),
          error: (error, stack) => _ErrorCard(
            message: error.toString(),
            onRetry: () => ref.invalidate(costsProvider),
          ),
          data: (value) {
            final budget = value['budget'] as Map?;
            if (!_loaded) {
              _loaded = true;
              if (budget != null) {
                _limit.text = ((budget['monthlyLimitMinor'] as int) / 100).toStringAsFixed(2);
                _currency.text = budget['currency'].toString();
                _enforce = budget['enforce'] == true;
              }
            }
            final month = (value['month'] as List? ?? const []).whereType<Map>();
            final entries = (value['entries'] as List? ?? const []).whereType<Map>();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bieżący miesiąc', style: Theme.of(context).textTheme.titleMedium),
                        if (month.isEmpty) const Text('Brak wpisów.'),
                        for (final row in month)
                          Text(
                            '${row['category'] == 'USAGE' ? 'Zużycie' : 'Subskrypcje'}: ${_money(row['amountMinor'] as int, row['currency'].toString())}',
                          ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Limit miesięczny zużycia', style: Theme.of(context).textTheme.titleMedium),
                        TextField(
                          controller: _limit,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Limit'),
                        ),
                        TextField(
                          controller: _currency,
                          decoration: const InputDecoration(labelText: 'Waluta (3 litery)'),
                        ),
                        SwitchListTile(
                          title: const Text('Blokuj start etapów po przekroczeniu'),
                          value: _enforce,
                          onChanged: (on) => setState(() => _enforce = on),
                        ),
                        FilledButton(
                          onPressed: () => _run(
                            () async {
                              await ref.read(apiClientProvider).request(
                                '/costs/budget',
                                method: 'POST',
                                data: {
                                  'monthlyLimitMinor':
                                      ((double.tryParse(_limit.text.trim()) ?? 0) * 100).round(),
                                  'currency': _currency.text.trim(),
                                  'enforce': _enforce,
                                },
                              );
                            },
                            'Limit zapisany.',
                          ),
                          child: const Text('Zapisz limit'),
                        ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Import CSV', style: Theme.of(context).textTheme.titleMedium),
                        const Text('Nagłówek: date,category,amount,currency,description (category: USAGE lub SUBSCRIPTION).'),
                        TextField(
                          controller: _csv,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(labelText: 'Zawartość CSV'),
                        ),
                        FilledButton(
                          onPressed: () => _run(
                            () async {
                              await ref.read(apiClientProvider).request(
                                '/costs/import',
                                method: 'POST',
                                data: {'csv': _csv.text},
                              );
                              _csv.clear();
                            },
                            'Zaimportowano wpisy.',
                          ),
                          child: const Text('Importuj'),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final entry in entries)
                  ListTile(
                    title: Text(entry['description'].toString()),
                    subtitle: Text('${entry['occurredOn']} · ${entry['category']}'),
                    trailing: Text(_money(entry['amountMinor'] as int, entry['currency'].toString())),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
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
          if (action != null) ...[const SizedBox(width: 12), action!],
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
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
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
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
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
    final activeStages = stages
        .where((stage) => stage['status'] != 'APPROVED')
        .length;
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
            Text(
              stage['title']?.toString() ?? 'Etap',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
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
                  message:
                      'Preview CI/CD nie jest skonfigurowane dla tego etapu.',
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
                  message: 'Zatwierdzenie wykonasz w szczegółach bota po zielonym CI i teście manualnym.',
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

Future<void> _openGitHubUrl(BuildContext context, Object? value) async {
  final uri = Uri.tryParse(value?.toString() ?? '');
  if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pull request nie ma prawidłowego adresu GitHub.'),
      ),
    );
    return;
  }
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
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
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : const [];
