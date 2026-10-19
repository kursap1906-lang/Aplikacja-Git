import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../theme.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bots = ref.watch(botsProvider);
    final session = ref.watch(sessionDataProvider);

    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 14),
        sliver: SliverToBoxAdapter(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _Eyebrow('COPILOT CONTROL CENTER'),
                SizedBox(height: 9),
                Text('Przegląd', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700)),
                SizedBox(height: 6),
                Text('Boty, etapy i decyzje wymagające Twojej uwagi.',
                    style: TextStyle(color: AppColors.muted)),
              ]),
            ),
            FilledButton.icon(
              onPressed: () => context.go('/bots/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nowy bot'),
            ),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 4, 26, 12),
        sliver: SliverToBoxAdapter(
          child: session.when(
            data: (data) {
              final user = data['user'];
              final displayName = user is Map ? user['displayName'] : null;
              return Text('Dzień dobry${displayName is String ? ', $displayName' : ''}.',
                  style: const TextStyle(color: AppColors.muted));
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => _InlineError(message: error.toString(), onRetry: () => ref.invalidate(sessionDataProvider)),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 8, 26, 20),
        sliver: SliverToBoxAdapter(
          child: bots.when(
            data: (items) {
              final running = items.where((bot) => bot['status'] == 'RUNNING').length;
              final stages = items.expand((bot) => _records(bot['stages'])).toList();
              final waiting = stages.where((stage) => stage['status'] == 'WAITING_APPROVAL').length;
              final pullRequests = stages.expand((stage) => _records(stage['pullRequests'])).length;

              return Wrap(spacing: 10, runSpacing: 10, children: [
                _StatTile(label: 'Aktywne boty', value: '${items.length}', icon: Icons.hub_outlined, color: AppColors.blue),
                _StatTile(label: 'W pracy', value: '$running', icon: Icons.sync_rounded, color: AppColors.mint),
                _StatTile(label: 'Czekają na decyzję', value: '$waiting', icon: Icons.hourglass_top_rounded, color: AppColors.amber),
                _StatTile(label: 'Pull requesty', value: '$pullRequests', icon: Icons.merge_type_rounded, color: AppColors.blue),
              ]);
            },
            loading: () => const LinearProgressIndicator(),
            error: (error, stack) => _InlineError(message: error.toString(), onRetry: () => ref.invalidate(botsProvider)),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 16),
        sliver: const SliverToBoxAdapter(
          child: Text('Twoje boty', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 40),
        sliver: bots.when(
          data: (items) => items.isEmpty
              ? SliverToBoxAdapter(
                  child: _EmptyBots(onCreate: () => context.go('/bots/new'), onAccounts: () => context.go('/accounts')),
                )
              : SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => _BotRow(
                    bot: items[index],
                    onOpen: () => context.go('/bots/${items[index]['id']}'),
                  ),
                ),
          loading: () => const SliverToBoxAdapter(child: LinearProgressIndicator()),
          error: (error, stack) => SliverToBoxAdapter(
            child: _InlineError(message: error.toString(), onRetry: () => ref.invalidate(botsProvider)),
          ),
        ),
      ),
    ]);
  }

  static List<Map<String, dynamic>> _records(Object? value) => value is List
      ? value.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
      : const [];
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(label,
      style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2));
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 192,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(children: [
              Icon(icon, color: color, size: 21),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              ])),
            ]),
          ),
        ),
      );
}

class _BotRow extends StatelessWidget {
  const _BotRow({required this.bot, required this.onOpen});
  final Map<String, dynamic> bot;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final stages = bot['stages'] is List ? bot['stages'] as List : const [];
    final active = stages.cast<Map>().where((stage) => stage['status'] != 'APPROVED').firstOrNull;
    final account = bot['githubAccount'] is Map ? bot['githubAccount'] as Map : const {};

    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.panelRaised,
              child: Text((bot['name'] as String? ?? 'B').characters.first.toUpperCase(),
                  style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bot['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('${bot['repository'] ?? ''} · @${account['login'] ?? ''}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ])),
            if (active is Map && active.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text('${active['number']}. ${active['title']}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            const SizedBox(width: 12),
            _StatusIndicator(bot['status']?.toString() ?? 'IDLE'),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ]),
        ),
      ),
    );
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator(this.status);
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'RUNNING' => AppColors.mint,
      'PAUSED' => AppColors.amber,
      'ERROR' => AppColors.coral,
      _ => AppColors.muted,
    };
    final label = switch (status) {
      'RUNNING' => 'W pracy',
      'PAUSED' => 'Wstrzymany',
      'ERROR' => 'Błąd',
      _ => 'Gotowy',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(5)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _EmptyBots extends StatelessWidget {
  const _EmptyBots({required this.onCreate, required this.onAccounts});
  final VoidCallback onCreate;
  final VoidCallback onAccounts;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Wrap(spacing: 24, runSpacing: 18, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const SizedBox(
              width: 280,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Nie masz jeszcze botów.', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text('Połącz konto GitHub i utwórz pierwszego bota dla wybranego repozytorium.',
                    style: TextStyle(color: AppColors.muted, height: 1.5)),
              ]),
            ),
            FilledButton.icon(onPressed: onAccounts, icon: const Icon(Icons.link_rounded), label: const Text('Połącz GitHub')),
            OutlinedButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_rounded), label: const Text('Dodaj bota')),
          ]),
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.coral),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted))),
            IconButton(tooltip: 'Ponów próbę', onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
          ]),
        ),
      );
}