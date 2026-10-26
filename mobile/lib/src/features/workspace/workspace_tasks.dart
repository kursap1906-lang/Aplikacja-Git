import 'package:flutter/material.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';
import 'workspace_analysis.dart';

const workspaceTaskPriorities = {
  'LOW': 'Niski',
  'NORMAL': 'Normalny',
  'HIGH': 'Wysoki',
  'URGENT': 'Pilny',
};
const workspaceTaskStatuses = {
  'TODO': 'Oczekuje',
  'IN_PROGRESS': 'W trakcie',
  'BLOCKED': 'Zablokowane',
  'COMPLETED': 'Gotowe',
};
typedef WorkspaceTaskDraft = ({
  String assigneeId,
  String title,
  String description,
  String priority,
});
typedef WorkspaceAssignee = ({String id, String name});

Future<WorkspaceTaskDraft?> showWorkspaceTaskEditor(
  BuildContext context, {
  required List<WorkspaceAssignee> assignees,
  String? selectedAssignee,
  WorkspaceTaskDraft? initial,
  Future<void> Function(WorkspaceTaskDraft)? onSave,
}) => showDialog<WorkspaceTaskDraft>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _TaskEditor(
    assignees: assignees,
    selectedAssignee: selectedAssignee,
    initial: initial,
    onSave: onSave,
  ),
);

class WorkspaceBotSelector extends StatelessWidget {
  const WorkspaceBotSelector({
    required this.bots,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final List<WorkspaceAssignee> bots;
  final String? selected;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        label: const Text('Wszystkie boty'),
        selected: selected == null,
        onSelected: enabled ? (_) => onChanged(null) : null,
      ),
      for (final bot in bots)
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: ChoiceChip(
            label: Text(bot.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            selected: selected == bot.id,
            onSelected: enabled ? (_) => onChanged(bot.id) : null,
          ),
        ),
    ],
  );
}

class _TaskEditor extends StatefulWidget {
  const _TaskEditor({
    required this.assignees,
    required this.selectedAssignee,
    required this.initial,
    required this.onSave,
  });
  final List<WorkspaceAssignee> assignees;
  final String? selectedAssignee;
  final WorkspaceTaskDraft? initial;
  final Future<void> Function(WorkspaceTaskDraft)? onSave;

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late final _description = TextEditingController(
    text: widget.initial?.description ?? '',
  );
  late String? _assignee = _initialAssignee();
  late String _priority = widget.initial?.priority ?? 'NORMAL';
  bool _saving = false;
  String? _error;

  String? _initialAssignee() {
    final id = widget.initial?.assigneeId ?? widget.selectedAssignee;
    return widget.assignees.any((bot) => bot.id == id) ? id : null;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final assignee = _assignee;
    if (assignee == null) {
      setState(() => _error = 'Wybierz bota.');
      return;
    }
    final draft = (
      assigneeId: assignee,
      title: _title.text.trim(),
      description: _description.text.trim(),
      priority: _priority,
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave?.call(draft);
      if (mounted) Navigator.pop(context, draft);
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
      title: Text(widget.initial == null ? 'Dodaj task' : 'Edytuj task'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _assignee,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Bot odpowiedzialny',
                  ),
                  items: [
                    for (final bot in widget.assignees)
                      DropdownMenuItem(value: bot.id, child: Text(bot.name)),
                  ],
                  validator: (value) => value == null ? 'Wybierz bota.' : null,
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _assignee = value),
                ),
                const SizedBox(height: 12),
                WorkspaceTextField(
                  controller: _title,
                  label: 'Tytuł taska',
                  maxLength: 200,
                  isRequired: true,
                  enabled: !_saving,
                ),
                WorkspaceTextField(
                  controller: _description,
                  label: 'Opis taska',
                  maxLength: 5000,
                  lines: 4,
                  enabled: !_saving,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _priority,
                  decoration: const InputDecoration(labelText: 'Priorytet'),
                  items: [
                    for (final priority in workspaceTaskPriorities.entries)
                      DropdownMenuItem(
                        value: priority.key,
                        child: Text(priority.value),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) setState(() => _priority = value);
                        },
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
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Zapisywanie…' : 'Zapisz task'),
        ),
      ],
    ),
  );
}

class WorkspaceTeamTasks extends StatefulWidget {
  const WorkspaceTeamTasks({
    required this.team,
    required this.api,
    required this.onChanged,
    super.key,
  });
  final WorkspaceTeam team;
  final ApiClient api;
  final VoidCallback onChanged;

  @override
  State<WorkspaceTeamTasks> createState() => _WorkspaceTeamTasksState();
}

class _WorkspaceTeamTasksState extends State<WorkspaceTeamTasks> {
  String? _selected;
  String? _busyTask;
  String? _error;
  int _statusGeneration = 0;

  Future<void> _edit([WorkspaceTask? task]) async {
    final result = await showWorkspaceTaskEditor(
      context,
      assignees: [
        for (final member in widget.team.members)
          (id: member.botId, name: member.name),
      ],
      selectedAssignee: _selected,
      initial: task == null
          ? null
          : (
              assigneeId: task.botId ?? '',
              title: task.title,
              description: task.description,
              priority: task.priority,
            ),
      onSave: (draft) async {
        final response = await widget.api.request(
          task == null
              ? '/workspace/teams/${Uri.encodeComponent(widget.team.id)}/tasks'
              : '/workspace/tasks/${Uri.encodeComponent(task.id)}',
          method: task == null ? 'POST' : 'PATCH',
          data: {
            'title': draft.title,
            'description': draft.description,
            'botId': draft.assigneeId,
            'priority': draft.priority,
          },
        );
        if (task == null) {
          parseWorkspaceTask(response['task']);
        } else if (response['ok'] != true) {
          throw const ApiException(
            'INVALID_WORKSPACE_RESPONSE',
            'Serwer nie potwierdził zapisu zadania.',
          );
        }
      },
    );
    if (result != null && mounted) widget.onChanged();
  }

  Future<void> _status(WorkspaceTask task, String status) async {
    setState(() {
      _busyTask = task.id;
      _error = null;
    });
    try {
      final response = await widget.api.updateProjectTask(
        taskId: task.id,
        status: status,
      );
      final updated = parseWorkspaceTask(response['task']);
      if (updated.id != task.id || updated.status != status) {
        throw const ApiException(
          'INVALID_WORKSPACE_RESPONSE',
          'Serwer nie potwierdził zmiany statusu.',
        );
      }
      if (mounted) widget.onChanged();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _busyTask = null;
          _statusGeneration++;
        });
      }
    }
  }

  Future<void> _delete(WorkspaceTask task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć task?'),
        content: Text(task.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
    setState(() {
      _busyTask = task.id;
      _error = null;
    });
    try {
      await widget.api.request(
        '/workspace/tasks/${Uri.encodeComponent(task.id)}',
        method: 'DELETE',
      );
      if (mounted) widget.onChanged();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyTask = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bots = [
      for (final member in widget.team.members)
        (id: member.botId, name: member.name),
    ];
    final selected = bots.any((bot) => bot.id == _selected) ? _selected : null;
    final tasks = widget.team.tasks
        .where((task) => selected == null || task.botId == selected)
        .toList();
    final names = {for (final bot in bots) bot.id: bot.name};
    return WorkspacePanel(
      title: 'Zadania zespołu',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceBotSelector(
            bots: bots,
            selected: selected,
            enabled: _busyTask == null,
            onChanged: (value) => setState(() => _selected = value),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: bots.isEmpty || _busyTask != null ? null : _edit,
                icon: const Icon(Icons.add),
                label: const Text('Dodaj task'),
              ),
              OutlinedButton(
                onPressed: bots.isEmpty || _busyTask != null
                    ? null
                    : () => showWorkspaceAnalysis(
                        context,
                        api: widget.api,
                        teamId: widget.team.id,
                        onChanged: widget.onChanged,
                      ),
                child: const Text('Analizuj dokument przez AI'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Analiza korzysta z zapisanych materiałów projektu. Przed wysłaniem pokażemy zasady i limit kosztu. Zapis taska nie uruchamia bota.',
          ),
          if (tasks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Brak zadań dla wybranych botów.'),
            ),
          for (final task in tasks)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${names[task.botId] ?? 'Bez przypisania'} · priorytet: ${workspaceTaskPriorities[task.priority]}',
                    ),
                    if (task.description.isNotEmpty) Text(task.description),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${task.id}-${task.status}-$_statusGeneration',
                      ),
                      initialValue: task.status,
                      decoration: const InputDecoration(
                        labelText: 'Status taska',
                      ),
                      items: [
                        for (final status in workspaceTaskStatuses.entries)
                          DropdownMenuItem(
                            value: status.key,
                            child: Text(status.value),
                          ),
                      ],
                      onChanged: _busyTask != null
                          ? null
                          : (value) {
                              if (value != null && value != task.status) {
                                _status(task, value);
                              }
                            },
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _busyTask != null
                              ? null
                              : () => _edit(task),
                          icon: const Icon(Icons.edit),
                          label: const Text('Edytuj task'),
                        ),
                        TextButton.icon(
                          onPressed: _busyTask != null
                              ? null
                              : () => _delete(task),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Usuń task'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_busyTask != null) const LinearProgressIndicator(),
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
