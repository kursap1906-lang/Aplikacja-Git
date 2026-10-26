import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_files_panel.dart';
import 'workspace_repository_picker.dart';
import 'workspace_shell.dart';
import 'workspace_tasks.dart';

Future<String?> showWorkspaceProjectEditor(
  BuildContext context, {
  required ApiClient api,
  required List<WorkspaceAccount> accounts,
  WorkspaceProject? project,
}) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _ProjectEditor(project: project, accounts: accounts, api: api),
);

class WorkspaceProjectsPage extends StatefulWidget {
  const WorkspaceProjectsPage({
    required this.projects,
    required this.teams,
    required this.accounts,
    required this.api,
    required this.onChanged,
    required this.onConnectAccounts,
    super.key,
  });

  final List<WorkspaceProject> projects;
  final List<WorkspaceTeam> teams;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;
  final VoidCallback onChanged;
  final VoidCallback onConnectAccounts;

  @override
  State<WorkspaceProjectsPage> createState() => _WorkspaceProjectsPageState();
}

class _WorkspaceProjectsPageState extends State<WorkspaceProjectsPage> {
  String? _selectedId;
  String? _downloadId;
  String? _error;

  Future<void> _edit([WorkspaceProject? project]) async {
    final id = await showWorkspaceProjectEditor(
      context,
      project: project,
      accounts: widget.accounts,
      api: widget.api,
    );
    if (id == null || !mounted) return;
    setState(() => _selectedId = id);
    widget.onChanged();
  }

  Future<void> _download(WorkspaceDocument document) async {
    setState(() {
      _downloadId = document.id;
      _error = null;
    });
    try {
      final bytes = await widget.api.downloadProjectDocument(
        documentId: document.id,
        version: document.version,
      );
      if (!mounted) return;
      await FilePicker.saveFile(
        fileName: document.filename,
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _error = 'Nie udało się pobrać PDF-a: $error');
      }
    } finally {
      if (mounted) setState(() => _downloadId = null);
    }
  }

  Widget _details(WorkspaceProject project) {
    final teams = widget.teams
        .where((team) => team.projectId == project.id)
        .toList();
    final memberNames = {
      for (final team in teams)
        for (final member in team.members) member.botId: member.name,
    };
    final done = project.tasks
        .where((task) => task.status == 'COMPLETED')
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _selectedId = null;
              _error = null;
            }),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Lista projektów'),
          ),
        ),
        WorkspacePanel(
          title: 'Szczegóły zadania',
          trailing: OutlinedButton.icon(
            onPressed: () => _edit(project),
            icon: const Icon(Icons.edit),
            label: const Text('Edytuj opis i materiały'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(project.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(
                project.repository ?? 'Brak przypisanego repozytorium',
              ),
              const SizedBox(height: 8),
              SelectableText(project.description),
              const SizedBox(height: 12),
              Text(
                '${teams.length} zespołów · $done/${project.tasks.length} ukończonych zadań',
              ),
              if (project.tasks.isNotEmpty)
                LinearProgressIndicator(value: done / project.tasks.length),
              const SizedBox(height: 12),
              const Text(
                'Opis i załączniki są wspólne dla wszystkich zespołów tego projektu.',
              ),
            ],
          ),
        ),
        WorkspacePanel(
          title: 'Opis zadania i PDF',
          child: SelectableText(
            project.brief.isEmpty
                ? 'Nie dodano jeszcze pełnego opisu zadania.'
                : project.brief,
          ),
        ),
        WorkspacePanel(
          title: 'Profil projektu · kontekst dla botów',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                project.repositoryContext.isEmpty
                    ? 'Nie zapisano jeszcze kontekstu repozytorium.'
                    : project.repositoryContext,
              ),
              const SizedBox(height: 12),
              const Text(
                'Skanowanie z AI będzie dostępne po konfiguracji OpenAI. Nie zastępujemy go samą listą plików repozytorium.',
              ),
            ],
          ),
        ),
        WorkspaceFilesPanel(
          key: ValueKey('project-files-${project.id}'),
          api: widget.api,
          collection: 'projects',
          ownerId: project.id,
          files: project.files,
          onChanged: widget.onChanged,
        ),
        if (project.documents.isNotEmpty)
          WorkspacePanel(
            title: 'Wcześniej zapisane dokumenty PDF',
            child: Column(
              children: [
                for (final document in project.documents)
                  ListTile(
                    leading: const Icon(Icons.picture_as_pdf),
                    title: Text(document.filename),
                    subtitle: Text('Wersja ${document.version}'),
                    trailing: IconButton(
                      tooltip: 'Pobierz ${document.filename}',
                      onPressed: _downloadId != null
                          ? null
                          : () => _download(document),
                      icon: const Icon(Icons.download),
                    ),
                  ),
                if (_downloadId != null) const LinearProgressIndicator(),
              ],
            ),
          ),
        WorkspacePanel(
          title: 'Zadania projektu',
          child: project.tasks.isEmpty
              ? const Text(
                  'Brak zapisanych zadań. Zadania i przypisania edytuje się w podglądzie zespołu.',
                )
              : Column(
                  children: [
                    for (final task in project.tasks)
                      ListTile(
                        leading: Icon(
                          task.status == 'COMPLETED'
                              ? Icons.check_circle
                              : Icons.task_alt,
                        ),
                        title: Text(task.title),
                        subtitle: Text(
                          '${task.botId == null ? 'Bez przypisania' : memberNames[task.botId] ?? 'Bot ${task.botId}'}'
                          ' · ${workspaceTaskStatuses[task.status]} · priorytet: ${workspaceTaskPriorities[task.priority]}'
                          '${task.description.isEmpty ? '' : '\n${task.description}'}',
                        ),
                      ),
                  ],
                ),
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.projects
        .where((project) => project.id == _selectedId)
        .firstOrNull;
    if (selected != null) return _details(selected);
    final connected = widget.accounts.any((account) => account.active);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspacePanel(
          title: 'Projekty i PDF',
          trailing: FilledButton.icon(
            onPressed: connected ? _edit : null,
            icon: const Icon(Icons.add),
            label: const Text('Dodaj projekt'),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jeden projekt może mieć wiele zespołów korzystających ze wspólnego repozytorium i materiałów.',
              ),
              if (!connected) ...[
                const SizedBox(height: 12),
                const Text(
                  'Do utworzenia projektu potrzebne jest aktywne konto GitHub.',
                ),
                OutlinedButton.icon(
                  onPressed: widget.onConnectAccounts,
                  icon: const Icon(Icons.link),
                  label: const Text('Połącz konto GitHub'),
                ),
              ],
              if (widget.projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nie masz jeszcze projektów zapisanych na serwerze.',
                  ),
                ),
            ],
          ),
        ),
        for (final project in widget.projects)
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_copy),
              title: Text(project.name),
              subtitle: Text(
                '${project.repository ?? 'Brak repozytorium'}'
                ' · ${project.files.length + project.documents.length} plików'
                ' · ${project.tasks.length} zadań',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() {
                _selectedId = project.id;
                _error = null;
              }),
            ),
          ),
      ],
    );
  }
}

class _ProjectEditor extends StatefulWidget {
  const _ProjectEditor({
    required this.api,
    required this.accounts,
    this.project,
  });

  final ApiClient api;
  final List<WorkspaceAccount> accounts;
  final WorkspaceProject? project;

  @override
  State<_ProjectEditor> createState() => _ProjectEditorState();
}

class _ProjectEditorState extends State<_ProjectEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late final _description = TextEditingController(
    text: widget.project?.description ?? '',
  );
  late final _brief = TextEditingController(text: widget.project?.brief ?? '');
  late final _context = TextEditingController(
    text: widget.project?.repositoryContext ?? '',
  );
  WorkspaceRepositorySelection? _repository;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [_name, _description, _brief, _context]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final repository = _repository;
    final project = widget.project;
    if (project == null && repository == null) {
      setState(() => _error = 'Wybierz główne konto GitHub i repozytorium.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        project == null
            ? '/workspace/projects'
            : '/workspace/projects/${Uri.encodeComponent(project.id)}',
        method: project == null ? 'POST' : 'PATCH',
        data: {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'brief': _brief.text.trim(),
          if (project != null) 'repositoryContext': _context.text.trim(),
          if (project == null && repository != null) ...{
            'githubAccountId': repository.accountId,
            'repository': repository.repository,
          },
        },
      );
      final String id;
      if (project == null) {
        id = requireCreatedId(response, 'project');
      } else {
        if (response['ok'] != true) {
          throw const ApiException(
            'INVALID_WORKSPACE_RESPONSE',
            'Serwer nie potwierdził zapisu projektu.',
          );
        }
        id = project.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        widget.project == null
            ? 'Dodaj projekt'
            : 'Edytuj opis i materiały projektu',
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkspaceTextField(
                  controller: _name,
                  label: 'Nazwa projektu',
                  maxLength: 120,
                  isRequired: true,
                  enabled: !_saving,
                ),
                WorkspaceTextField(
                  controller: _description,
                  label: 'Krótki opis projektu',
                  maxLength: 5000,
                  lines: 2,
                  enabled: !_saving,
                ),
                if (widget.project == null)
                  WorkspaceRepositoryPicker(
                    api: widget.api,
                    accounts: widget.accounts,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _repository = value),
                  )
                else
                  SelectableText(
                    'Repozytorium: ${widget.project!.repository ?? 'Brak przypisania'}. Edycja materiałów nie zmienia repozytorium zespołów.',
                  ),
                const SizedBox(height: 12),
                WorkspaceTextField(
                  controller: _brief,
                  label: 'Pełny opis zadania dla botów',
                  maxLength: 100000,
                  lines: 5,
                  enabled: !_saving,
                ),
                if (widget.project != null)
                  WorkspaceTextField(
                    controller: _context,
                    label: 'Kontekst repozytorium dla botów',
                    maxLength: 100000,
                    lines: 5,
                    enabled: !_saving,
                  ),
                const Text(
                  'Opis i materiały są współdzielone przez zespoły projektu. Pliki dodasz w szczegółach po zapisaniu projektu.',
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Zapisz projekt'),
        ),
      ],
    ),
  );
}
