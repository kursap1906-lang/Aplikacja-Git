import 'package:flutter/material.dart';

import 'workspace_data.dart';
import 'workspace_shell.dart';

class WorkspaceMetricCard extends StatelessWidget {
  const WorkspaceMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
    this.color,
    this.onTap,
    this.progress,
    super.key,
  });

  final String title, value;
  final String? subtitle;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: (color ?? Colors.grey).withValues(alpha: .3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    onTap == null ? icon : Icons.north_east,
                    color: accent,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
              if (progress != null) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(8),
                  color: accent,
                  backgroundColor: accent.withValues(alpha: .12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WorkspaceDashboard extends StatelessWidget {
  const WorkspaceDashboard({
    required this.data,
    required this.onReload,
    required this.onCosts,
    required this.onTeam,
    required this.onCreateTeam,
    super.key,
  });
  final WorkspaceData data;
  final VoidCallback onReload, onCosts, onCreateTeam;
  final ValueChanged<String> onTeam;

  @override
  Widget build(BuildContext context) {
    final tasks = {
      for (final project in data.projects)
        for (final task in project.tasks) task.id: task,
      for (final team in data.teams)
        for (final task in team.tasks) task.id: task,
    };
    final bots = {
      for (final team in data.teams)
        for (final bot in team.members) bot.botId,
    };
    final waiting = data.teams
        .where(
          (team) => team.members.any(
            (member) => member.stages.any(
              (stage) => stage.status == 'WAITING_APPROVAL',
            ),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pulpit organizacji',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Odśwież dane',
              onPressed: onReload,
              icon: const Icon(Icons.refresh),
            ),
            FilledButton.icon(
              onPressed: onCreateTeam,
              icon: const Icon(Icons.add),
              label: const Text('Nowy zespół'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 600
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: width,
                  child: WorkspaceMetricCard(
                    title: 'Wszystkie boty',
                    value: '${bots.length}',
                    icon: Icons.smart_toy_outlined,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: WorkspaceMetricCard(
                    title: 'Otwarte zadania',
                    value:
                        '${tasks.values.where((task) => task.status != 'COMPLETED').length}',
                    icon: Icons.checklist,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: WorkspaceMetricCard(
                    title: 'Zakończone zadania',
                    value:
                        '${tasks.values.where((task) => task.status == 'COMPLETED').length}',
                    icon: Icons.done_all,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: WorkspaceMetricCard(
                    title: 'Koszt abonamentów / mies.',
                    value: 'Brak danych',
                    subtitle: 'GitHub nie udostępnia cen subskrypcji w raporcie pakietów. Nie szacujemy faktur.',
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: onCosts,
                  ),
                ),
              ],
            );
          },
        ),
        WorkspaceMetricCard(
          title: 'Zespoły oczekujące na potwierdzenie',
          value: '${waiting.length}',
          subtitle: 'Etapy wymagające decyzji właściciela',
          icon: Icons.fact_check_outlined,
          color: Colors.orange,
          onTap: () {
            if (waiting.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Brak etapów oczekujących na potwierdzenie.'),
                ),
              );
            } else {
              onTeam(waiting.first.id);
            }
          },
        ),
        WorkspaceMetricCard(
          title: 'Pozostałe kredyty AI',
          value: 'Pakiety kont GitHub',
          subtitle: 'Osobne liczniki i paski wykorzystania każdego konta. Nie sumujemy różnych jednostek ani nieznanych sald.',
          icon: Icons.toll_outlined,
          color: Colors.indigo,
          onTap: onCosts,
        ),
        WorkspacePanel(
          title: 'Twoje zespoły',
          trailing: Chip(label: Text('${data.teams.length} zespoły')),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('Projekty: ${data.projects.length}')),
                  Chip(label: Text('Definicje botów: ${data.roles.length}')),
                ],
              ),
              if (data.teams.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Nie masz jeszcze zespołów zapisanych na serwerze.',
                  ),
                ),
              for (final team in data.teams)
                ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.groups_outlined),
                  ),
                  title: Text(team.name),
                  subtitle: Text(
                    '${team.members.length} botów · ${team.tasks.length} zadań',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTeam(team.id),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
