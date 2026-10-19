import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

final sessionProvider = FutureProvider<bool>((ref) async {
  final token = await ref.watch(apiClientProvider).currentSession();
  return token != null;
});

final sessionDataProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).request('/session'),
);

final botsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/bots');
  final bots = result['bots'];
  if (bots is! List) return const [];
  return bots.whereType<Map>().map((bot) => Map<String, dynamic>.from(bot)).toList();
});

final botProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, id) async {
  final result = await ref.watch(apiClientProvider).request('/bots/$id');
  return Map<String, dynamic>.from(result['bot'] as Map);
});

final pullRequestProvider = FutureProvider.family<Map<String, dynamic>, ({String botId, String pullRequestId})>(
  (ref, ids) async {
    final result = await ref.watch(apiClientProvider).request(
      '/bots/${ids.botId}/pull-requests/${ids.pullRequestId}',
    );
    return Map<String, dynamic>.from(result);
  },
);

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/notifications');
  final notifications = result['notifications'];
  if (notifications is! List) return const [];
  return notifications.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
});