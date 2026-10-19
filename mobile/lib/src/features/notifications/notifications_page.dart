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
    final color = _color(notification['type']?.toString() ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .1),
          child: Icon(_icon(notification['type']?.toString() ?? ''), color: color, size: 20),
        ),
        title: Row(children: [
          Expanded(child: Text(notification['title']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
          if (unread) const Icon(Icons.circle, size: 8, color: AppColors.blue),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(notification['body']?.toString() ?? '', style: const TextStyle(color: AppColors.muted)),
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

  static Color _color(String type) => switch (type.toUpperCase()) {
        'ERROR' || 'TESTS_FAILED' || 'BOT_ERROR' => AppColors.coral,
        'APPROVAL' || 'WAITING_APPROVAL' || 'PR_READY' => AppColors.amber,
        'SUCCESS' || 'STAGE_APPROVED' || 'PROJECT_COMPLETED' => AppColors.mint,
        _ => AppColors.blue,
      };

  static IconData _icon(String type) => switch (type.toUpperCase()) {
        'ERROR' || 'TESTS_FAILED' || 'BOT_ERROR' => Icons.error_outline_rounded,
        'APPROVAL' || 'WAITING_APPROVAL' || 'PR_READY' => Icons.hourglass_top_rounded,
        'SUCCESS' || 'STAGE_APPROVED' || 'PROJECT_COMPLETED' => Icons.check_circle_outline_rounded,
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