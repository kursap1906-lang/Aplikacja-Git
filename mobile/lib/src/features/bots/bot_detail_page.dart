import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class BotDetailPage extends ConsumerWidget {
  const BotDetailPage({required this.botId, super.key});
  final String botId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final botState = ref.watch(botProvider(botId));
    return botState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _Message(message: error.toString(), onRetry: () => ref.invalidate(botProvider(botId))),
      data: (bot) {
        final stages = _records(bot['stages'])..sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 30, 26, 10),
            sliver: SliverToBoxAdapter(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('SZCZEGÓŁY BOTA', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(height: 9),
                Text(bot['name']?.toString() ?? '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 5),
                Text('${bot['repository']} · ${bot['githubAccount'] is Map ? (bot['githubAccount'] as Map)['login'] : ''}',
                    style: const TextStyle(color: AppColors.muted)),
              ])),
            ])),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 10, 26, 10),
            sliver: SliverToBoxAdapter(child: Card(
              child: Padding(
                padding: const EdgeInsets.all(17),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Główny prompt', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(bot['systemPrompt']?.toString() ?? '', style: const TextStyle(color: AppColors.muted, height: 1.5)),
                  const SizedBox(height: 8),
                  const Text('Zadania korzystają z podglądowego GitHub REST API i wymagają odpowiedniego planu Copilot oraz uprawnień repozytorium.',
                      style: TextStyle(color: AppColors.amber, fontSize: 12)),
                ]),
              ),
            )),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 10),
            sliver: const SliverToBoxAdapter(child: Text('Etapy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 40),
            sliver: SliverList.builder(
              itemCount: stages.length,
              itemBuilder: (context, index) => _StageCard(
                botId: botId,
                stage: stages[index],
                onRefresh: () => ref.invalidate(botProvider(botId)),
              ),
            ),
          ),
        ]);
      },
    );
  }

  static List<Map<String, dynamic>> _records(Object? value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : [];
}

class _StageCard extends ConsumerStatefulWidget {
  const _StageCard({required this.botId, required this.stage, required this.onRefresh});
  final String botId;
  final Map<String, dynamic> stage;
  final VoidCallback onRefresh;

  @override
  ConsumerState<_StageCard> createState() => _StageCardState();
}

class _StageCardState extends ConsumerState<_StageCard> {
  bool _busy = false;
  String? _error;
  String? _taskUrl;

  Future<void> _perform(String action, {String? reason}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).request(
        '/stages/${widget.stage['id']}/$action',
        method: 'POST',
        data: {'reason': ?reason},
      );
      if (mounted) {
        if (action == 'start') {
          final task = result['task'];
          final url = task is Map ? task['url'] : null;
          if (url is String) _taskUrl = url;
        }
        widget.onRefresh();
        ref.invalidate(botsProvider);
        ref.invalidate(notificationsProvider);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refreshCopilotTask() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(apiClientProvider).request(
        '/stages/${widget.stage['id']}/task',
      );
      if (mounted) {
        final task = result['task'];
        setState(() {
          _error = 'Status Copilota: ${task is Map ? task['state'] ?? 'nieznany' : 'nieznany'}';
          final url = task is Map ? task['url'] : null;
          if (url is String) _taskUrl = url;
        });
        widget.onRefresh();
        ref.invalidate(botsProvider);
        ref.invalidate(notificationsProvider);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCopilotTask() async {
    final url = _taskUrl;
    if (url == null) return;

    final uri = Uri.tryParse(url);
    if (uri == null
        || uri.scheme != 'https'
        || !{'github.com', 'api.github.com'}.contains(uri.host)) {
      setState(() => _error = 'GitHub zwrócił nieprawidłowy adres zadania.');
      return;
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => _error = 'Nie udało się otworzyć zadania GitHub.');
    }
  }

  Future<void> _requestChanges() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReasonDialog(),
    );
    if (reason != null && reason.isNotEmpty) await _perform('request-changes', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final status = stage['status']?.toString() ?? 'PENDING';
    final color = switch (status) {
      'APPROVED' => AppColors.mint,
      'WAITING_APPROVAL' => AppColors.amber,
      'FAILED' => AppColors.coral,
      'RUNNING' || 'TESTING' => AppColors.blue,
      'CANCELLED' => AppColors.coral,
      _ => AppColors.muted,
    };
    final criteria = stage['acceptanceCriteria'] is List ? stage['acceptanceCriteria'] as List : const [];
    final pullRequests = stage['pullRequests'] is List ? stage['pullRequests'] as List : const [];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('ETAP ${stage['number']}', style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w700)),
            Text(stage['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
            _StageStatus(status: status, color: color),
          ]),
          const SizedBox(height: 10),
          Text(stage['description']?.toString() ?? '', style: const TextStyle(color: AppColors.muted, height: 1.5)),
          if (stage['branchName'] is String) ...[
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.account_tree_outlined, size: 15, color: AppColors.blue),
              const SizedBox(width: 7),
              SelectableText(stage['branchName'].toString(), style: const TextStyle(color: AppColors.blue, fontSize: 12)),
            ]),
          ],
          if (criteria.isNotEmpty) ...[
            const SizedBox(height: 15),
            const Text('KRYTERIA AKCEPTACJI', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            for (final criterion in criteria)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_box_outline_blank_rounded, size: 15, color: AppColors.muted)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(criterion.toString(), style: const TextStyle(fontSize: 13))),
                ]),
              ),
          ],
          if (pullRequests.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(),
            for (final rawPr in pullRequests.whereType<Map>())
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.merge_type_rounded, color: AppColors.blue),
                title: Text('PR #${rawPr['number']}: ${rawPr['title'] ?? 'Pull request'}'),
                subtitle: Text('${rawPr['status'] ?? ''} · CI: ${rawPr['ciStatus'] ?? 'brak danych'}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                trailing: IconButton(
                  tooltip: 'Podgląd diffu i testów',
                  onPressed: () => context.go('/bots/${widget.botId}/pull-requests/${rawPr['id']}'),
                  icon: const Icon(Icons.description_outlined, size: 18),
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.coral, fontSize: 12)),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
          if (status == 'WAITING_APPROVAL') ...[
            const Divider(height: 28),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: _busy ? null : () => _perform('approve'),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Zatwierdź etap'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _requestChanges,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Poproś o poprawki'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _perform('pause'),
                icon: const Icon(Icons.pause_rounded),
                label: const Text('Wstrzymaj'),
              ),
            ]),
            const SizedBox(height: 9),
            const Text('Akceptacja etapu nie scala pull requesta i nie uruchamia agenta.',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
          ],
          if (status == 'RUNNING') ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              if (_taskUrl != null)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openCopilotTask,
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Otwórz zadanie GitHub'),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _refreshCopilotTask,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Sprawdź status Copilota'),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Wznowienie, wstrzymanie i anulowanie zadania nie są obsługiwane przez GitHub Agent Tasks API.',
                  style: TextStyle(color: AppColors.muted, fontSize: 11)),
            ),
          ],
          if (status == 'PAUSED') ...[
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('Zadanie GitHub może nadal działać; synchronizuj jego stan poniżej. API nie udostępnia wznawiania.',
                  style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _refreshCopilotTask,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sprawdź status Copilota'),
            ),
            if (_taskUrl != null)
              TextButton.icon(
                onPressed: _busy ? null : _openCopilotTask,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Otwórz zadanie GitHub'),
              ),
          ],
          if (status == 'PENDING' || status == 'CHANGES_REQUESTED' || status == 'FAILED')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Tooltip(
                message: 'Uruchamia zadanie GitHub Copilot cloud agent dla repozytorium i gałęzi przypisanych do tego bota.',
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _perform('start'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Uruchom zadanie Copilot'),
                ),
              ),
            ),
          if (status == 'APPROVED') ...[
            const SizedBox(height: 12),
            const Text('Zaakceptowano. Następny etap wymaga osobnego uruchomienia, które nie jest teraz dostępne przez publiczne API.',
                style: TextStyle(color: AppColors.mint, fontSize: 12)),
          ],
        ]),
      ),
    );
  }

}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Zakres poprawek'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Opisz wymagane poprawki'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Anuluj')),
          FilledButton(
            onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Wyślij uwagi'),
          ),
        ],
      );
}

class _StageStatus extends StatelessWidget {
  const _StageStatus({required this.status, required this.color});
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      'PENDING' => 'Oczekuje',
      'RUNNING' => 'W pracy',
      'TESTING' => 'Testowanie',
      'WAITING_APPROVAL' => 'Wymaga decyzji',
      'APPROVED' => 'Zatwierdzony',
      'CHANGES_REQUESTED' => 'Poprawki',
      'FAILED' => 'Błąd',
      'PAUSED' => 'Wstrzymany',
      'CANCELLED' => 'Anulowany',
      _ => status,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_outlined, color: AppColors.amber, size: 30),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Ponów')),
            ]),
          ),
        ),
      );
}