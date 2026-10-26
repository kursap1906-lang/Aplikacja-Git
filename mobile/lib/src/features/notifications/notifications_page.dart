import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/providers.dart';
import '../../theme.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 18),
        sliver: SliverToBoxAdapter(child: Row(children: [
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ZDARZENIA', style: TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w700)),
            SizedBox(height: 8),
            Text('Powiadomienia', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          ])),
          IconButton(tooltip: 'Odśwież', onPressed: () => ref.invalidate(notificationsProvider), icon: const Icon(Icons.refresh_rounded)),
        ])),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(26, 0, 26, 35),
        sliver: notifications.when(
          loading: () => const SliverToBoxAdapter(child: LinearProgressIndicator()),
          error: (error, stack) => SliverToBoxAdapter(child: _ErrorMessage(message: error.toString(), onRetry: () => ref.invalidate(notificationsProvider))),
          data: (items) => items.isEmpty
              ? const SliverToBoxAdapter(child: _EmptyNotifications())
              : SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) => _NotificationRow(notification: items[index]),
                ),
        ),
      ),
    ]);
  }
}

class _NotificationRow extends ConsumerWidget {
  const _NotificationRow({required this.notification});
  final Map<String, dynamic> notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = notification['readAt'] == null;
    final type = notification['type']?.toString() ?? '';
    final color = _color(type);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(_icon(notification['type']?.toString() ?? ''), color: color, size: 20),
        ),
        title: Row(children: [
          Expanded(
            child: Text(
              _title(type),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (unread) const Icon(Icons.circle, size: 8, color: AppColors.blue),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            _body(type),
            style: const TextStyle(color: AppColors.muted),
          ),
        ),
        trailing: unread
            ? IconButton(
                tooltip: 'Oznacz jako przeczytane',
                onPressed: () async {
                  try {
                    await ref.read(apiClientProvider).request(
                      '/notifications/${notification['id']}/read',
                      method: 'PATCH',
                    );
                    ref.invalidate(notificationsProvider);
                  } on ApiException catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                    }
                  }
                },
                icon: const Icon(Icons.done_rounded),
              )
            : const Icon(Icons.check_rounded, color: AppColors.muted),
      ),
    );
  }

  static String _title(String type) => switch (type.toUpperCase()) {
        'COPILOT_TASK_STARTED' => 'Copilot rozpoczął zadanie',
        'COPILOT_TASK_QUEUED' => 'Zadanie Copilot oczekuje w kolejce',
        'COPILOT_TASK_IN_PROGRESS' => 'Copilot pracuje nad zadaniem',
        'COPILOT_TASK_COMPLETED' => 'Copilot zakończył zadanie',
        'COPILOT_TASK_FAILED' => 'Zadanie Copilot zakończyło się błędem',
        'COPILOT_TASK_TIMED_OUT' => 'Przekroczono czas wykonywania zadania Copilot',
        'COPILOT_TASK_CANCELLED' => 'Zadanie Copilot zostało anulowane',
        'COPILOT_TASK_IDLE' => 'Zadanie Copilot jest bezczynne',
        'COPILOT_TASK_WAITING_FOR_USER' => 'Copilot czeka na Twoje działanie',
        _ => 'Powiadomienie',
      };

  static String _body(String type) => switch (type.toUpperCase()) {
        'COPILOT_TASK_STARTED' =>
          'GitHub przyjął zadanie do wykonania. Możesz sprawdzić jego status w szczegółach bota.',
        'COPILOT_TASK_COMPLETED' =>
          'Sprawdź wynik pracy i pull request przed zatwierdzeniem etapu.',
        'COPILOT_TASK_FAILED' =>
          'GitHub zgłosił błąd podczas wykonywania zadania. Sprawdź jego status i spróbuj ponownie.',
        'COPILOT_TASK_TIMED_OUT' =>
          'GitHub przekroczył limit czasu wykonywania zadania. Sprawdź jego status.',
        'COPILOT_TASK_CANCELLED' => 'GitHub zgłosił anulowanie zadania.',
        'COPILOT_TASK_WAITING_FOR_USER' =>
          'GitHub czeka na Twoje działanie, zanim będzie mógł kontynuować.',
        'COPILOT_TASK_QUEUED' => 'Zadanie czeka na rozpoczęcie przez GitHub.',
        'COPILOT_TASK_IN_PROGRESS' => 'GitHub wykonuje zadanie.',
        'COPILOT_TASK_IDLE' => 'GitHub zgłosił, że zadanie jest bezczynne.',
        _ => 'Zarejestrowano nowe zdarzenie dotyczące zadania Copilot.',
      };

  static Color _color(String type) => switch (type.toUpperCase()) {
        'ERROR' || 'TESTS_FAILED' || 'BOT_ERROR' || 'COPILOT_TASK_FAILED' || 'COPILOT_TASK_TIMED_OUT' => AppColors.coral,
        'APPROVAL' || 'WAITING_APPROVAL' || 'PR_READY' || 'COPILOT_TASK_WAITING_FOR_USER' => AppColors.amber,
        'SUCCESS' || 'STAGE_APPROVED' || 'PROJECT_COMPLETED' || 'COPILOT_TASK_COMPLETED' => AppColors.mint,
        _ => AppColors.blue,
      };

  static IconData _icon(String type) => switch (type.toUpperCase()) {
        'ERROR' || 'TESTS_FAILED' || 'BOT_ERROR' || 'COPILOT_TASK_FAILED' || 'COPILOT_TASK_TIMED_OUT' => Icons.error_outline_rounded,
        'APPROVAL' || 'WAITING_APPROVAL' || 'PR_READY' || 'COPILOT_TASK_WAITING_FOR_USER' => Icons.hourglass_top_rounded,
        'SUCCESS' || 'STAGE_APPROVED' || 'PROJECT_COMPLETED' || 'COPILOT_TASK_COMPLETED' => Icons.check_circle_outline_rounded,
        _ => Icons.notifications_none_rounded,
      };
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(children: [
            Icon(Icons.notifications_none_rounded, color: AppColors.muted),
            SizedBox(width: 12),
            Expanded(child: Text('Nie ma nowych powiadomień.', style: TextStyle(color: AppColors.muted))),
          ]),
        ),
      );
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.coral),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: const TextStyle(color: AppColors.muted))),
            IconButton(tooltip: 'Ponów', onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
          ]),
        ),
      );
}