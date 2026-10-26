import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'demo_collaboration.dart';
import 'workspace_data.dart';
import 'workspace_files_panel.dart';
import 'workspace_projects_page.dart';
import 'workspace_shell.dart';
import 'workspace_tasks.dart';
import 'workspace_repository_picker.dart';
import 'workspace_team_activity.dart';

class WorkspaceTeamsPage extends StatefulWidget {
  const WorkspaceTeamsPage({
    required this.data,
    required this.accounts,
    required this.api,
    required this.onChanged,
    this.initialTeamId,
    super.key,
  });

  final WorkspaceData data;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;
  final VoidCallback onChanged;
  final String? initialTeamId;

  @override
  State<WorkspaceTeamsPage> createState() => _WorkspaceTeamsPageState();
}

class _WorkspaceTeamsPageState extends State<WorkspaceTeamsPage> {
  late String? _selectedId = widget.initialTeamId;
  bool _creating = false;
  int _tab = 0;

  Future<void> _constructionTeam() async {
    final id = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _ConstructionTeamDialog(api: widget.api, accounts: widget.accounts),
    );
    if (id == null || !mounted) return;
    setState(() {
      _selectedId = id;
      _tab = 0;
    });
    widget.onChanged();
  }

  @override
  void didUpdateWidget(covariant WorkspaceTeamsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTeamId != widget.initialTeamId &&
        widget.initialTeamId != null) {
      _selectedId = widget.initialTeamId;
      _creating = false;
      _tab = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_creating) {
      return _TeamCreator(
        data: widget.data,
        accounts: widget.accounts,
        api: widget.api,
        onChanged: widget.onChanged,
        onCancel: () => setState(() => _creating = false),
        onSaved: (id) {
          setState(() {
            _selectedId = id;
            _creating = false;
            _tab = 0;
          });
          widget.onChanged();
        },
      );
    }
    final team = widget.data.teams
        .where((team) => team.id == _selectedId)
        .firstOrNull;
    if (team == null) {
      return WorkspacePanel(
        title: 'Wszystkie zespoły AI',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.data.teams.isEmpty)
              const Text('Nie masz jeszcze zespołów zapisanych na serwerze.'),
            for (final team in widget.data.teams)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(team.name),
                  subtitle: Text(
                    '${team.members.length} botów · ${team.tasks.length} zadań',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() {
                    _selectedId = team.id;
                    _tab = 0;
                  }),
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _constructionTeam,
              icon: const Icon(Icons.construction),
              label: const Text(
                'Dodaj BuildApp — 5 botów web/mobile dla budowlańców',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => setState(() => _creating = true),
                icon: const Icon(Icons.add),
                label: const Text('Utwórz zespół'),
              ),
            ),
          ],
        ),
      );
    }

    final project = widget.data.projects
        .where((project) => project.id == team.projectId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _selectedId = null),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Lista zespołów'),
          ),
        ),
        WorkspacePanel(
          title: team.name,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(team.description),
              Text(
                project == null
                    ? 'Brak projektu — starszy zespół.'
                    : '${project.name} · ${project.repository ?? 'Brak repozytorium'}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, label) in [
                    'Zadania',
                    'Boty i GitHub',
                    'Współpraca',
                    'PDF',
                    'Podgląd botów',
                  ].indexed)
                    ChoiceChip(
                      label: Text(label),
                      selected: _tab == index,
                      onSelected: (_) => setState(() => _tab = index),
                    ),
                ],
              ),
            ],
          ),
        ),
        if (_tab == 4)
          WorkspaceTeamActivity(
            key: ValueKey('activity-${team.id}'),
            team: team,
            api: widget.api,
            onChanged: widget.onChanged,
          ),
        Visibility(
          visible: _tab == 0,
          maintainState: true,
          child: WorkspaceTeamTasks(
            key: ValueKey('tasks-${team.id}'),
            team: team,
            api: widget.api,
            onChanged: widget.onChanged,
          ),
        ),
        Visibility(
          visible: _tab == 1,
          maintainState: true,
          child: _TeamMembers(
            key: ValueKey('members-${team.id}'),
            team: team,
            roles: widget.data.roles,
            accounts: widget.accounts,
            api: widget.api,
            onChanged: widget.onChanged,
          ),
        ),
        Visibility(
          visible: _tab == 2,
          maintainState: true,
          child: _TeamHierarchy(
            key: ValueKey('hierarchy-${team.id}'),
            team: team,
            api: widget.api,
            onChanged: widget.onChanged,
          ),
        ),
        if (project != null)
          Visibility(
            visible: _tab == 3,
            maintainState: true,
            child: _ProjectMaterials(
              project: project,
              accounts: widget.accounts,
              api: widget.api,
              onChanged: widget.onChanged,
            ),
          ),
        if (_tab == 3 && project == null)
          const WorkspacePanel(
            title: 'Materiały',
            child: Text('Ten starszy zespół nie ma przypisanego projektu.'),
          ),
      ],
    );
  }
}

class _ConstructionTeamDialog extends StatefulWidget {
  const _ConstructionTeamDialog({required this.api, required this.accounts});
  final ApiClient api;
  final List<WorkspaceAccount> accounts;
  @override
  State<_ConstructionTeamDialog> createState() =>
      _ConstructionTeamDialogState();
}

class _ConstructionTeamDialogState extends State<_ConstructionTeamDialog> {
  WorkspaceRepositorySelection? _selection;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final selection = _selection;
    if (selection == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.api.request(
        '/workspace/templates/construction',
        method: 'POST',
        data: {
          'githubAccountId': selection.accountId,
          'repository': selection.repository,
        },
      );
      if (result['teamId'] is! String) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził utworzenia zespołu.',
        );
      }
      if (mounted) Navigator.pop(context, result['teamId'] as String);
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
      title: const Text('BuildApp — zespół 5 botów'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Architekt/Tech Lead, Web UX, Flutter Mobile, Backend i QA/DevOps. Powstanie projekt, pięć ról i instancji oraz pięć zadań. Żaden bot nie zostanie uruchomiony. Ponowne dodanie tej samej konfiguracji nie tworzy duplikatów.',
              ),
              const SizedBox(height: 16),
              WorkspaceRepositoryPicker(
                api: widget.api,
                accounts: widget.accounts,
                enabled: !_saving,
                onChanged: (value) => setState(() => _selection = value),
              ),
              if (_saving) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: _saving || _selection == null ? null : _save,
          child: const Text('Zapisz zespół i 5 botów'),
        ),
      ],
    ),
  );
}

class _TeamCreator extends StatefulWidget {
  const _TeamCreator({
    required this.data,
    required this.accounts,
    required this.api,
    required this.onChanged,
    required this.onCancel,
    required this.onSaved,
  });
  final WorkspaceData data;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;
  final VoidCallback onChanged;
  final VoidCallback onCancel;
  final ValueChanged<String> onSaved;

  @override
  State<_TeamCreator> createState() => _TeamCreatorState();
}

class _TeamCreatorState extends State<_TeamCreator> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _members = <String, String?>{};
  final _tasks = <WorkspaceTaskDraft>[];
  String? _projectId;
  String? _selectedBot;
  String? _error;
  int _step = 0;
  bool _saving = false;
  bool _hasPendingFiles = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _project() async {
    final id = await showWorkspaceProjectEditor(
      context,
      api: widget.api,
      accounts: widget.accounts,
    );
    if (id == null || !mounted) return;
    setState(() => _projectId = id);
    widget.onChanged();
  }

  Future<void> _toggle(WorkspaceRole role, bool selected) async {
    if (selected) {
      if (_members.length >= 20) {
        setState(() => _error = 'Zespół może mieć maksymalnie 20 botów.');
        return;
      }
      setState(() {
        _members[role.id] = null;
        _error = null;
      });
      return;
    }
    if (_tasks.any((task) => task.assigneeId == role.id)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Usunąć bota z planu?'),
          content: Text('Usuniemy także niezapisane taski bota ${role.name}.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Anuluj'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Usuń z planu'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      _members.remove(role.id);
      _tasks.removeWhere((task) => task.assigneeId == role.id);
      if (_selectedBot == role.id) _selectedBot = null;
    });
  }

  Future<void> _task([int? index]) async {
    if (index == null && _tasks.length >= 100) {
      setState(
        () => _error = 'W jednym planie można zapisać maksymalnie 100 tasków.',
      );
      return;
    }
    final draft = await showWorkspaceTaskEditor(
      context,
      assignees: [
        for (final role in widget.data.roles.where(
          (role) => _members.containsKey(role.id),
        ))
          (id: role.id, name: role.name),
      ],
      selectedAssignee: _selectedBot,
      initial: index == null ? null : _tasks[index],
    );
    if (draft == null || !mounted) return;
    setState(() {
      if (index == null) {
        _tasks.add(draft);
      } else {
        _tasks[index] = draft;
      }
    });
  }

  Future<void> _save() async {
    final active = widget.accounts
        .where((account) => account.active)
        .map((account) => account.id)
        .toSet();
    String? error;
    var step = _step;
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 100 ||
        _description.text.trim().length > 2000) {
      error = 'Podaj nazwę zespołu (do 100 znaków) i opis do 2000 znaków.';
      step = 0;
    } else if (!widget.data.projects.any(
      (project) => project.id == _projectId && project.repository != null,
    )) {
      error = 'Wybierz zapisany projekt z repozytorium GitHub.';
      step = 0;
    } else if (_members.isEmpty ||
        _members.keys.any(
          (id) => !widget.data.roles.any((role) => role.id == id),
        )) {
      error = 'Wybierz co najmniej jedną aktualną definicję bota.';
      step = 1;
    } else if (_members.values.any(
      (account) => account == null || !active.contains(account),
    )) {
      error = 'Wybierz aktywne konto GitHub dla każdego bota.';
      step = 2;
    } else if (_hasPendingFiles) {
      error =
          'Wyślij wybrane pliki lub usuń je z listy przed zapisaniem zespołu.';
      step = 3;
    }
    if (error != null) {
      setState(() {
        _error = error;
        _step = step;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/teams',
        method: 'POST',
        data: {
          'name': _name.text.trim(),
          'description': _description.text.trim(),
          'projectId': _projectId,
          'members': [
            for (final entry in _members.entries)
              {'definitionId': entry.key, 'githubAccountId': entry.value},
          ],
          'tasks': [
            for (final task in _tasks)
              {
                'definitionId': task.assigneeId,
                'title': task.title,
                'description': task.description,
                'priority': task.priority,
              },
          ],
        },
      );
      final id = requireCreatedId(response, 'team');
      if (mounted) widget.onSaved(id);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.data.projects
        .where((project) => project.id == _projectId)
        .firstOrNull;
    final roles = widget.data.roles
        .where((role) => _members.containsKey(role.id))
        .toList();
    final active = widget.accounts.where((account) => account.active).toList();
    final names = {for (final role in roles) role.id: role.name};
    return PopScope(
      canPop: !_saving,
      child: WorkspacePanel(
        title: 'Nowy zespół AI',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (index, label) in [
                  'Projekt',
                  'Boty',
                  'GitHub',
                  'PDF',
                  'Zadanie',
                  'Zapis',
                ].indexed)
                  ChoiceChip(
                    label: Text(label),
                    selected: _step == index,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _step = index),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_step == 0) ...[
              WorkspaceTextField(
                controller: _name,
                label: 'Nazwa zespołu',
                maxLength: 100,
                enabled: !_saving,
              ),
              WorkspaceTextField(
                controller: _description,
                label: 'Opis zespołu',
                maxLength: 2000,
                lines: 3,
                enabled: !_saving,
              ),
              DropdownButtonFormField<String>(
                key: ValueKey('team-project-${project?.id}'),
                initialValue: project?.id,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Wspólny projekt'),
                items: [
                  for (final project in widget.data.projects.where(
                    (project) => project.repository != null,
                  ))
                    DropdownMenuItem(
                      value: project.id,
                      child: Text('${project.name} · ${project.repository}'),
                    ),
                ],
                onChanged: _saving || _hasPendingFiles
                    ? null
                    : (id) => setState(() => _projectId = id),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving || _hasPendingFiles || active.isEmpty
                    ? null
                    : _project,
                icon: const Icon(Icons.add),
                label: const Text('Dodaj wspólny projekt'),
              ),
              if (_hasPendingFiles)
                const Text(
                  'Przed zmianą projektu wyślij lub usuń wybrane pliki w kroku PDF.',
                ),
              const Text(
                'Projekt i materiały można współdzielić między zespołami. Każdy zespół dostanie oddzielne instancje botów.',
              ),
              if (active.isEmpty)
                const Text('Najpierw połącz konto GitHub w ustawieniach.'),
            ],
            if (_step == 1) ...[
              const Text(
                'Wybierz własne role. Prompt zostanie skopiowany do nowych instancji; nie uruchomimy ich automatycznie.',
              ),
              if (widget.data.roles.isEmpty)
                const Text('Najpierw utwórz definicje w zakładce Boty i role.'),
              for (final role in widget.data.roles)
                CheckboxListTile(
                  value: _members.containsKey(role.id),
                  title: Text(role.name),
                  subtitle: Text(role.role),
                  onChanged: _saving
                      ? null
                      : (selected) => _toggle(role, selected == true),
                ),
            ],
            if (_step == 2) ...[
              Text(
                'Wspólne repozytorium: ${project?.repository ?? 'Najpierw wybierz projekt'}. Dostęp każdego konta sprawdzimy przy zapisie.',
              ),
              if (roles.isEmpty) const Text('Najpierw wybierz boty zespołu.'),
              for (final role in roles)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'team-account-${role.id}-${_members[role.id]}',
                    ),
                    initialValue:
                        active.any((account) => account.id == _members[role.id])
                        ? _members[role.id]
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '${role.name} — konto GitHub',
                    ),
                    items: [
                      for (final account in active)
                        DropdownMenuItem(
                          value: account.id,
                          child: Text('@${account.login}'),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (account) =>
                              setState(() => _members[role.id] = account),
                  ),
                ),
            ],
            if (project != null)
              Visibility(
                key: ValueKey('wizard-materials-${project.id}'),
                visible: _step == 3,
                maintainState: true,
                child: _ProjectMaterials(
                  project: project,
                  accounts: widget.accounts,
                  api: widget.api,
                  onChanged: widget.onChanged,
                  onPendingFilesChanged: (pending) =>
                      setState(() => _hasPendingFiles = pending),
                ),
              ),
            if (_step == 3 && project == null)
              const Text('Najpierw wybierz projekt.'),
            if (_step == 4) ...[
              WorkspaceBotSelector(
                bots: [
                  for (final role in roles) (id: role.id, name: role.name),
                ],
                selected: _selectedBot,
                enabled: !_saving,
                onChanged: (value) => setState(() => _selectedBot = value),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _saving || roles.isEmpty ? null : _task,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj task'),
                  ),
                  const OutlinedButton(
                    onPressed: null,
                    child: Text('Analiza AI po zapisaniu zespołu'),
                  ),
                ],
              ),
              const Text(
                'Plan tasków zapisze się razem z zespołem. Analizę materiałów uruchomisz po zapisaniu, w zadaniach zespołu.',
              ),
              for (final (index, task) in _tasks.indexed)
                if (_selectedBot == null || task.assigneeId == _selectedBot)
                  Card(
                    child: ListTile(
                      title: Text(task.title),
                      subtitle: Text(
                        '${names[task.assigneeId]} · priorytet: ${workspaceTaskPriorities[task.priority]}\n${task.description}',
                      ),
                      onTap: _saving ? null : () => _task(index),
                      trailing: IconButton(
                        tooltip: 'Usuń z planu',
                        onPressed: _saving
                            ? null
                            : () => setState(() => _tasks.removeAt(index)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
            ],
            if (_step == 5) ...[
              Text('Zespół: ${_name.text.trim()}'),
              Text('Projekt: ${project?.name ?? 'Nie wybrano'}'),
              Text('Nowe instancje: ${roles.length} · taski: ${_tasks.length}'),
              const SizedBox(height: 12),
              const Text(
                'Zapis jest atomowy. Nie uruchamia SDK, nie wypycha zmian i nie tworzy PR. Najpierw będzie wymagana Twoja zgoda.',
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_saving) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: _saving ? null : widget.onCancel,
                  child: const Text('Anuluj'),
                ),
                if (_step > 0)
                  OutlinedButton(
                    onPressed: _saving ? null : () => setState(() => _step--),
                    child: const Text('Wstecz'),
                  ),
                if (_step < 5)
                  FilledButton(
                    onPressed: _saving ? null : () => setState(() => _step++),
                    child: const Text('Dalej'),
                  ),
                if (_step == 5)
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: const Text('Zapisz zespół'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectMaterials extends StatelessWidget {
  const _ProjectMaterials({
    required this.project,
    required this.accounts,
    required this.api,
    required this.onChanged,
    this.onPendingFilesChanged,
  });
  final WorkspaceProject project;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;
  final VoidCallback onChanged;
  final ValueChanged<bool>? onPendingFilesChanged;

  Future<void> _edit(BuildContext context) async {
    final id = await showWorkspaceProjectEditor(
      context,
      api: api,
      accounts: accounts,
      project: project,
    );
    if (id != null && context.mounted) onChanged();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      WorkspacePanel(
        title: 'Opis zadania i PDF',
        trailing: OutlinedButton(
          onPressed: () => _edit(context),
          child: const Text('Edytuj wspólny opis'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Te materiały są wspólne dla wszystkich zespołów projektu.',
            ),
            const SizedBox(height: 12),
            SelectableText(
              project.brief.isEmpty
                  ? 'Nie dodano jeszcze opisu zadania.'
                  : project.brief,
            ),
            if (project.repositoryContext.isNotEmpty) ...[
              const SizedBox(height: 12),
              SelectableText(project.repositoryContext),
            ],
            if (project.documents.isNotEmpty)
              const Text(
                'Wcześniej zapisane wersje PDF pobierzesz w szczegółach projektu.',
              ),
          ],
        ),
      ),
      WorkspaceFilesPanel(
        key: ValueKey('team-project-files-${project.id}'),
        api: api,
        collection: 'projects',
        ownerId: project.id,
        files: project.files,
        onChanged: onChanged,
        onPendingFilesChanged: onPendingFilesChanged,
      ),
    ],
  );
}

class _TeamMembers extends StatefulWidget {
  const _TeamMembers({
    required this.team,
    required this.roles,
    required this.accounts,
    required this.api,
    required this.onChanged,
    super.key,
  });
  final WorkspaceTeam team;
  final List<WorkspaceRole> roles;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;
  final VoidCallback onChanged;

  @override
  State<_TeamMembers> createState() => _TeamMembersState();
}

class _TeamMembersState extends State<_TeamMembers> {
  bool _busy = false;
  String? _error;

  Future<void> _add() async {
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _MemberEditor(
        team: widget.team,
        roles: widget.roles,
        accounts: widget.accounts,
        api: widget.api,
      ),
    );
    if (added == true && mounted) widget.onChanged();
  }

  Future<void> _remove(WorkspaceMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Odłączyć bota ${member.name}?'),
        content: const Text(
          'Najpierw przenieś lub usuń jego zadania. Historia instancji pozostanie zapisana; nie jest to usunięcie definicji roli.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odłącz bota'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.request(
        '/workspace/teams/${Uri.encodeComponent(widget.team.id)}/members/${Uri.encodeComponent(member.id)}',
        method: 'DELETE',
      );
      if (mounted) widget.onChanged();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = {
      for (final account in widget.accounts) account.id: account,
    };
    return WorkspacePanel(
      title: 'Instancje botów i konta GitHub',
      trailing: OutlinedButton.icon(
        onPressed: _busy || widget.team.members.length >= 20 ? null : _add,
        icon: const Icon(Icons.add),
        label: const Text('Dodaj bota do zespołu'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Każdy wpis to oddzielna instancja z własnymi zadaniami, historią i kontem. Zapis nie uruchamia SDK.',
          ),
          for (final member in widget.team.members)
            ListTile(
              leading: const Icon(Icons.smart_toy),
              title: Text(member.name),
              subtitle: Text(
                'Instancja: ${member.botId}\nGitHub: ${accounts[member.githubAccountId] == null ? 'Konto ${member.githubAccountId}' : '@${accounts[member.githubAccountId]!.login}'} · status: ${member.status}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'Odłącz ${member.name}',
                onPressed: _busy || member.status != 'IDLE'
                    ? null
                    : () => _remove(member),
                icon: const Icon(Icons.person_remove_outlined),
              ),
            ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}

class _MemberEditor extends StatefulWidget {
  const _MemberEditor({
    required this.team,
    required this.roles,
    required this.accounts,
    required this.api,
  });
  final WorkspaceTeam team;
  final List<WorkspaceRole> roles;
  final List<WorkspaceAccount> accounts;
  final ApiClient api;

  @override
  State<_MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<_MemberEditor> {
  String? _definition;
  String? _account;
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    if (_definition == null || _account == null) {
      setState(() => _error = 'Wybierz definicję bota i aktywne konto GitHub.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/teams/${Uri.encodeComponent(widget.team.id)}/members',
        method: 'POST',
        data: {'definitionId': _definition, 'githubAccountId': _account},
      );
      requireCreatedId(response, 'member');
      if (mounted) Navigator.pop(context, true);
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.team.members
        .map((member) => member.definitionId)
        .toSet();
    final roles = widget.roles
        .where((role) => !existing.contains(role.id))
        .toList();
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('Dodaj nową instancję bota'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (roles.isEmpty)
                const Text(
                  'Nie ma nowych definicji do dodania. Utwórz własnego bota w zakładce Boty i role.',
                ),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Definicja bota'),
                isExpanded: true,
                items: [
                  for (final role in roles)
                    DropdownMenuItem(value: role.id, child: Text(role.name)),
                ],
                onChanged: _saving
                    ? null
                    : (id) => setState(() => _definition = id),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Konto GitHub instancji',
                ),
                isExpanded: true,
                items: [
                  for (final account in widget.accounts.where(
                    (account) => account.active,
                  ))
                    DropdownMenuItem(
                      value: account.id,
                      child: Text('@${account.login}'),
                    ),
                ],
                onChanged: _saving
                    ? null
                    : (id) => setState(() => _account = id),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sprawdzimy prawo zapisu wybranego konta w repozytorium projektu.',
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: _saving || roles.isEmpty ? null : _save,
            child: Text(_saving ? 'Zapisywanie…' : 'Dodaj instancję'),
          ),
        ],
      ),
    );
  }
}

class _TeamHierarchy extends StatefulWidget {
  const _TeamHierarchy({
    required this.team,
    required this.api,
    required this.onChanged,
    super.key,
  });
  final WorkspaceTeam team;
  final ApiClient api;
  final VoidCallback onChanged;

  @override
  State<_TeamHierarchy> createState() => _TeamHierarchyState();
}

class _TeamHierarchyState extends State<_TeamHierarchy> {
  late Map<String, String> _parents = _savedParents();
  late String _version = widget.team.updatedAt;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  Map<String, String> _savedParents() => {
    for (final member in widget.team.members) member.id: ?member.parentId,
  };

  @override
  void didUpdateWidget(covariant _TeamHierarchy oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty && oldWidget.team.updatedAt != widget.team.updatedAt) {
      _parents = _savedParents();
      _version = widget.team.updatedAt;
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        '/workspace/teams/${Uri.encodeComponent(widget.team.id)}/hierarchy',
        method: 'PATCH',
        data: {
          'updatedAt': _version,
          'members': [
            for (final member in widget.team.members)
              {'id': member.id, 'parentId': _parents[member.id]},
          ],
        },
      );
      if (response['ok'] != true) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził zapisu hierarchii.',
        );
      }
      if (!mounted) return;
      setState(() => _dirty = false);
      widget.onChanged();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final outdated = _dirty && _version != widget.team.updatedAt;
    return WorkspacePanel(
      title: 'Współpraca zespołu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (outdated)
            const Text(
              'Zespół zmienił się od rozpoczęcia edycji. Wczytaj aktualną hierarchię przed kolejną zmianą.',
            )
          else
            DemoCollaboration(
              enabled: !_saving,
              caption: 'Kliknij bota, aby wybrać przełożonego. Strzałki pokazują hierarchię. Zapisz zmiany przyciskiem poniżej; cykle są zablokowane.',
              members: [
                for (final member in widget.team.members)
                  (id: member.id, name: member.name, role: 'Instancja zespołu'),
              ],
              parents: _parents,
              onChanged: (parents) => setState(() {
                _parents = parents;
                _dirty = true;
                _error = null;
              }),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              FilledButton(
                onPressed: _saving || !_dirty || outdated ? null : _save,
                child: const Text('Zapisz hierarchię'),
              ),
              OutlinedButton(
                onPressed: _saving
                    ? null
                    : () {
                        setState(() {
                          _parents = _savedParents();
                          _version = widget.team.updatedAt;
                          _dirty = false;
                          _error = null;
                        });
                        widget.onChanged();
                      },
                child: const Text('Wczytaj aktualną hierarchię'),
              ),
            ],
          ),
          if (_saving) const LinearProgressIndicator(),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
