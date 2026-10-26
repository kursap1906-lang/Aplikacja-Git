import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';

final sessionProvider = FutureProvider<bool>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    await api.loadSession();
    return true;
  } on ApiException catch (error) {
    if (error.code != 'UNAUTHENTICATED') rethrow;
    await api.forgetSession();
    return false;
  }
}, retry: (retryCount, error) => null);

final sessionDataProvider = FutureProvider<Map<String, dynamic>>(
  (ref) => ref.watch(apiClientProvider).loadSession(),
  retry: (retryCount, error) => null,
);

final botsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/bots');
  final bots = result['bots'];
  if (bots is! List) return const [];
  return bots
      .whereType<Map>()
      .map((bot) => Map<String, dynamic>.from(bot))
      .toList();
});

final projectsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final result = await ref.watch(apiClientProvider).request('/projects');
  final projects = result['projects'];
  if (projects is! List) return const [];
  return projects
      .whereType<Map>()
      .map((project) => Map<String, dynamic>.from(project))
      .toList();
});

final projectTasksProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final result = await ref.watch(apiClientProvider).request('/tasks');
  final tasks = result['tasks'];
  if (tasks is! List) return const [];
  return tasks
      .whereType<Map>()
      .map((task) => Map<String, dynamic>.from(task))
      .toList();
});

final projectCollaborationProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, projectId) async {
      final result = await ref
          .watch(apiClientProvider)
          .request('/projects/$projectId/collaboration');
      return Map<String, dynamic>.from(result);
    });

final scheduleProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/schedule');
  return Map<String, dynamic>.from(result['schedule'] as Map);
});

final costsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/costs');
  return Map<String, dynamic>.from(result);
});

final teamsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final result = await ref.watch(apiClientProvider).request('/teams');
  final teams = result['teams'];
  if (teams is! List) return const [];
  return teams
      .whereType<Map>()
      .map((team) => Map<String, dynamic>.from(team))
      .toList();
});

final botProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, id) async {
      final result = await ref.watch(apiClientProvider).request('/bots/$id');
      return Map<String, dynamic>.from(result['bot'] as Map);
    });

final pullRequestProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, ({String botId, String pullRequestId})>((
      ref,
      ids,
    ) async {
      final result = await ref
          .watch(apiClientProvider)
          .request('/bots/${ids.botId}/pull-requests/${ids.pullRequestId}');
      return Map<String, dynamic>.from(result);
    });

final githubRepositoriesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      accountId,
    ) async {
      final response = await ref
          .watch(apiClientProvider)
          .request('/github/accounts/$accountId/repositories');
      final repositories = response['repositories'];
      if (repositories is! List) return const [];
      return repositories
          .whereType<Map>()
          .map((repository) => Map<String, dynamic>.from(repository))
          .toList();
    });

final notificationsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final result = await ref.watch(apiClientProvider).request('/notifications');
  final notifications = result['notifications'];
  if (notifications is! List) return const [];
  return notifications
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
});
