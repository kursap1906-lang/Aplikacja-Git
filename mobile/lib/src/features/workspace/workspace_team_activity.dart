import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import 'workspace_data.dart';
import 'workspace_shell.dart';
import 'workspace_agent_dialog.dart';

class WorkspaceTeamActivity extends StatefulWidget {
  const WorkspaceTeamActivity({
    required this.team,
    required this.api,
    required this.onChanged,
    super.key,
  });
  final WorkspaceTeam team;
  final ApiClient api;
  final VoidCallback onChanged;
  @override
  State<WorkspaceTeamActivity> createState() => _WorkspaceTeamActivityState();
}

class _WorkspaceTeamActivityState extends State<WorkspaceTeamActivity> {
  Timer? _timer;
  bool _busy = false;
  String? _error;
  final _states = <String, String>{};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (widget.team.members.any(
        (member) => member.stages.any(
          (stage) => ['RUNNING', 'PAUSED', 'TESTING'].contains(stage.status),
        ),
      )) {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      for (final member in widget.team.members) {
        for (final stage in member.stages.where(
          (stage) => ['RUNNING', 'PAUSED', 'TESTING'].contains(stage.status),
        )) {
          final response = await widget.api.request('/stages/${stage.id}/task');
          final task = response['task'];
          if (task is! Map<String, dynamic> || task['state'] is! String) {
            throw const ApiException(
              'INVALID_WORKSPACE_RESPONSE',
              'Nieprawidłowy status GitHub Agents.',
            );
          }
          if (!mounted) return;
          setState(() => _states[stage.id] = task['state'] as String);
        }
      }
      if (mounted) widget.onChanged();
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => WorkspacePanel(
    title: 'Boty zespołu — podgląd pracy',
    trailing: IconButton(
      tooltip: 'Odśwież pracę botów',
      onPressed: _busy ? null : _refresh,
      icon: const Icon(Icons.refresh),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Status aktywnych etapów odświeżamy co 15 sekund, gdy ten zespół jest otwarty. Każdy bot ma jedną stałą gałąź roboczą. Zadania kończą się dopiero po Twoim review.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (final member in widget.team.members)
          Builder(
            builder: (context) {
              final tasks = widget.team.tasks
                  .where((task) => task.botId == member.botId)
                  .toList();
              final stage = member.stages
                  .where(
                    (stage) =>
                        !['APPROVED', 'CANCELLED'].contains(stage.status),
                  )
                  .firstOrNull;
              final task =
                  tasks
                      .where((task) => task.status == 'IN_PROGRESS')
                      .firstOrNull ??
                  tasks.where((task) => task.status == 'TODO').firstOrNull;
              final waiting = stage?.status == 'WAITING_APPROVAL';
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            waiting
                                ? Icons.fact_check_outlined
                                : Icons.smart_toy_outlined,
                            color: waiting
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              member.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(
                              waiting
                                  ? 'Twoja akceptacja'
                                  : stage == null
                                  ? 'Gotowy'
                                  : _states[stage.id] ?? stage.status,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        stage == null
                            ? task?.title ?? 'Brak oczekujących zadań'
                            : 'Aktualny etap: ${stage.title}',
                      ),
                      Text(
                        'Zadania: ${tasks.where((task) => task.status == 'COMPLETED').length}/${tasks.length} ukończone',
                      ),
                      SelectableText(
                        'Gałąź: ccc/bot-${member.botId}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          if (task != null)
                            OutlinedButton.icon(
                              onPressed: () => showWorkspaceAgent(
                                context,
                                api: widget.api,
                                task: task,
                                onChanged: widget.onChanged,
                              ),
                              icon: Icon(
                                stage == null
                                    ? Icons.play_arrow
                                    : Icons.monitor,
                              ),
                              label: Text(
                                stage == null
                                    ? 'Start zadania'
                                    : 'Podgląd zadania',
                              ),
                            ),
                          if (member.stages.isNotEmpty)
                            TextButton(
                              onPressed: () =>
                                  context.go('/bots/${member.botId}'),
                              child: const Text('Etapy i review'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    ),
  );
}
