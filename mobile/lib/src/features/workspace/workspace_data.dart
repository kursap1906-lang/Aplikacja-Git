import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';

typedef WorkspaceRole = ({
  String id,
  String name,
  String role,
  String description,
  String systemPrompt,
  List<String> skills,
});
typedef WorkspaceFile = ({String id, String filename, int sizeBytes});
typedef WorkspaceDocument = ({String id, String filename, int version});
typedef WorkspaceProject = ({
  String id,
  String name,
  String description,
  String? repository,
  String? mainGithubAccountId,
  String brief,
  String repositoryContext,
  List<WorkspaceFile> files,
  List<WorkspaceDocument> documents,
  List<WorkspaceTask> tasks,
});
typedef WorkspaceSchedule = ({
  String timezone,
  bool enabled,
  List<int> days,
  String startTime,
  String endTime,
});
typedef WorkspaceStage = ({String id, String title, String status});
typedef WorkspaceMember = ({
  String id,
  String botId,
  String? parentId,
  String? definitionId,
  String name,
  String status,
  String githubAccountId,
  WorkspaceSchedule? schedule,
  List<WorkspaceStage> stages,
});
typedef WorkspaceTask = ({
  String id,
  String title,
  String description,
  String? botId,
  String? teamId,
  String status,
  String priority,
});
typedef WorkspaceTeam = ({
  String id,
  String name,
  String description,
  String? projectId,
  String updatedAt,
  List<WorkspaceMember> members,
  List<WorkspaceTask> tasks,
});
typedef WorkspaceRepository = ({String id, String fullName, bool canPush});
typedef WorkspaceRepositoryPage = ({
  List<WorkspaceRepository> repositories,
  int? nextPage,
});
typedef WorkspaceAccount = ({
  String id,
  String login,
  bool active,
  List<String> scopes,
});
typedef WorkspaceAnalysis = ({
  String id,
  String requestKey,
  String status,
  String model,
  int? estimatedCostMicros,
  int reservationHeldMicros,
  String? errorMessage,
  String? summary,
  int? addedTaskCount,
});
typedef WorkspaceAnalysisInfo = ({
  bool enabled,
  String model,
  int maximumCostMicros,
  int monthlyBudgetMicros,
  List<WorkspaceAnalysis> analyses,
});
typedef WorkspaceSdkPolicy = ({int monthlyExtraLimitMinor, String updatedAt});
typedef WorkspaceQuota = ({
  String name,
  bool unlimited,
  num entitlement,
  num used,
  num remainingPercentage,
  num overage,
  bool overageAllowed,
  String? resetDate,
});
typedef WorkspaceCreditAccount = ({
  String id,
  String login,
  bool active,
  String? refreshStatus,
  String? fetchedAt,
  bool? autoAvailable,
  bool quotaKnown,
  List<WorkspaceQuota> quotas,
  String? errorMessage,
});
typedef WorkspaceCosts = ({
  WorkspaceSdkPolicy? sdkPolicy,
  bool sdkExecutionAvailable,
  bool metadataEnabled,
  List<WorkspaceCreditAccount> accounts,
  String aiMonth,
  String aiModel,
  int aiSpentMicros,
  int aiReservedMicros,
  int aiUnknownCount,
  List<({String kind, String status, int? costMicros})> aiRecent,
});

Never _invalidResponse() => throw const ApiException(
  'INVALID_WORKSPACE_RESPONSE',
  'Serwer zwrócił nieprawidłowe dane obszaru roboczego.',
);

Map<String, dynamic> _object(Object? value) =>
    value is Map<String, dynamic> ? value : _invalidResponse();
String _text(Object? value) => value is String ? value : _invalidResponse();
String _id(Object? value) {
  final id = _text(value);
  return id.isNotEmpty ? id : _invalidResponse();
}

String? _nullableId(Object? value) => value == null ? null : _id(value);
String? _nullableText(Object? value) => value == null ? null : _text(value);
bool _boolean(Object? value) => value is bool ? value : _invalidResponse();
int _integer(Object? value) =>
    value is int && value >= 0 ? value : _invalidResponse();
List<T> _list<T>(Object? value, T Function(Object?) parse) => value is List
    ? value.map(parse).toList(growable: false)
    : _invalidResponse();
String _code(Object? value, Set<String> options) {
  final code = _text(value);
  return options.contains(code) ? code : _invalidResponse();
}

WorkspaceFile parseWorkspaceFile(Object? value) {
  final file = _object(value);
  return (
    id: _id(file['id']),
    filename: _text(file['filename']),
    sizeBytes: _integer(file['sizeBytes']),
  );
}

WorkspaceTask parseWorkspaceTask(Object? value) {
  final task = _object(value);
  return (
    id: _id(task['id']),
    title: _text(task['title']),
    description: _text(task['description']),
    botId: _nullableId(task['botId']),
    teamId: _nullableId(task['teamId']),
    status: _code(task['status'], {
      'TODO',
      'IN_PROGRESS',
      'BLOCKED',
      'COMPLETED',
    }),
    priority: _code(task['priority'], {'LOW', 'NORMAL', 'HIGH', 'URGENT'}),
  );
}

WorkspaceAnalysis parseWorkspaceAnalysis(
  Object? value, {
  required String teamId,
}) {
  final job = _object(value);
  if (job['kind'] != 'TEAM_TASKS' || job['teamId'] != teamId) {
    _invalidResponse();
  }
  final status = _code(job['status'], {
    'QUEUED',
    'RUNNING',
    'COMPLETED',
    'FAILED',
    'UNKNOWN',
  });
  final cost = job['estimatedCostMicros'] == null
      ? null
      : _integer(job['estimatedCostMicros']);
  final reserved = _integer(job['reservationHeldMicros']);
  final pending = {'QUEUED', 'RUNNING', 'UNKNOWN'}.contains(status);
  if ((pending && (cost != null || reserved != 1000000)) ||
      (!pending && (cost == null || cost > 1000000 || reserved != 0))) {
    _invalidResponse();
  }
  String? summary;
  int? added;
  if (status == 'COMPLETED') {
    final result = _object(job['result']);
    summary = _id(result['summary']);
    added = _integer(result['addedTaskCount']);
    final taskIds = _list(result['taskIds'], _id);
    if (added > 100 ||
        taskIds.length != added ||
        taskIds.toSet().length != taskIds.length) {
      _invalidResponse();
    }
  }
  final message = _nullableText(job['errorMessage']);
  if ({'FAILED', 'UNKNOWN'}.contains(status) &&
      (message == null || message.isEmpty)) {
    _invalidResponse();
  }
  return (
    id: _id(job['id']),
    requestKey: _id(job['requestKey']),
    status: status,
    model: _id(job['model']),
    estimatedCostMicros: cost,
    reservationHeldMicros: reserved,
    errorMessage: message,
    summary: summary,
    addedTaskCount: added,
  );
}

WorkspaceAnalysisInfo parseWorkspaceAnalysisInfo(
  Map<String, dynamic> value, {
  required String teamId,
}) {
  final maximum = _integer(value['maximumCostMicros']);
  final monthly = _integer(value['monthlyBudgetMicros']);
  if (maximum != 1000000 || monthly != 10000000) _invalidResponse();
  final jobs = _list(
    value['analyses'],
    (job) => parseWorkspaceAnalysis(job, teamId: teamId),
  );
  if (jobs.length > 10 ||
      jobs.map((job) => job.id).toSet().length != jobs.length) {
    _invalidResponse();
  }
  return (
    enabled: _boolean(value['enabled']),
    model: _id(value['model']),
    maximumCostMicros: maximum,
    monthlyBudgetMicros: monthly,
    analyses: jobs,
  );
}

WorkspaceSdkPolicy parseWorkspaceSdkPolicy(Object? value) {
  final policy = _object(value);
  final limit = _integer(policy['monthlyExtraLimitMinor']);
  final updatedAt = _id(policy['updatedAt']);
  if (limit > 1000000 || DateTime.tryParse(updatedAt) == null) {
    _invalidResponse();
  }
  return (monthlyExtraLimitMinor: limit, updatedAt: updatedAt);
}

num _quotaNumber(Object? value, {num minimum = 0}) =>
    value is num && value.isFinite && value >= minimum
    ? value
    : _invalidResponse();

WorkspaceCosts parseWorkspaceCosts(Map<String, dynamic> value) {
  final sdk = _object(value['sdk']);
  final ai = _object(value['openai']);
  if (sdk['model'] != 'auto' ||
      sdk['currency'] != 'USD' ||
      ai['currency'] != 'USD' ||
      ai['maximumAnalysisCostMicros'] != 1000000 ||
      ai['globalMonthlyBudgetMicros'] != 10000000 ||
      sdk['providerBudgetManagedByApplication'] != false) {
    _invalidResponse();
  }
  return (
    sdkPolicy: sdk['policy'] == null
        ? null
        : parseWorkspaceSdkPolicy(sdk['policy']),
    sdkExecutionAvailable: _boolean(sdk['executionAvailable']),
    metadataEnabled: _boolean(sdk['metadataEnabled']),
    accounts: _list(sdk['accounts'], (value) {
      final account = _object(value);
      final metadata = account['metadata'] == null
          ? null
          : _object(account['metadata']);
      final status = metadata == null
          ? null
          : _code(metadata['status'], {'QUEUED', 'RUNNING', 'READY', 'FAILED'});
      final fetched = metadata == null
          ? null
          : _nullableText(metadata['fetchedAt']);
      final rawQuota = metadata?['quota'];
      final quotaKnown = rawQuota != null;
      if (status == 'READY' && (!quotaKnown || fetched == null)) {
        _invalidResponse();
      }
      final quotas = quotaKnown
          ? _object(_object(rawQuota)['quotaSnapshots'])
          : <String, dynamic>{};
      return (
        id: _id(account['id']),
        login: _id(account['login']),
        active: _text(account['status']) == 'ACTIVE',
        refreshStatus: status,
        fetchedAt: fetched,
        autoAvailable: metadata?['autoAvailable'] == null
            ? null
            : _boolean(metadata!['autoAvailable']),
        quotaKnown: quotaKnown,
        errorMessage: metadata == null
            ? null
            : _nullableText(metadata['errorMessage']),
        quotas: [
          for (final entry in quotas.entries)
            (() {
              final quota = _object(entry.value);
              final unlimited = _boolean(quota['isUnlimitedEntitlement']);
              final entitlement = _quotaNumber(
                quota['entitlementRequests'],
                minimum: -1,
              );
              if (!unlimited && entitlement < 0) _invalidResponse();
              return (
                name: entry.key,
                unlimited: unlimited,
                entitlement: entitlement,
                used: _quotaNumber(quota['usedRequests']),
                remainingPercentage: _quotaNumber(
                  quota['remainingPercentage'],
                  minimum: -double.maxFinite,
                ),
                overage: _quotaNumber(quota['overage']),
                overageAllowed: _boolean(
                  quota['overageAllowedWithExhaustedQuota'],
                ),
                resetDate: _nullableText(quota['resetDate']),
              );
            })(),
        ],
      );
    }),
    aiMonth: _id(ai['month']),
    aiModel: _id(ai['model']),
    aiSpentMicros: _integer(ai['spentMicros']),
    aiReservedMicros: _integer(ai['reservedMicros']),
    aiUnknownCount: _integer(ai['unknownCount']),
    aiRecent: _list(ai['recent'], (value) {
      final job = _object(value);
      final status = _code(job['status'], {
        'QUEUED',
        'RUNNING',
        'COMPLETED',
        'FAILED',
        'UNKNOWN',
      });
      final cost = job['estimatedCostMicros'] == null
          ? null
          : _integer(job['estimatedCostMicros']);
      if (({'COMPLETED', 'FAILED'}.contains(status) && cost == null) ||
          ({'QUEUED', 'RUNNING', 'UNKNOWN'}.contains(status) && cost != null)) {
        _invalidResponse();
      }
      return (
        kind: _code(job['kind'], {
          'TEAM_TASKS',
          'REPOSITORY_CONTEXT',
          'DIAGNOSTIC',
        }),
        status: status,
        costMicros: cost,
      );
    }),
  );
}

class WorkspaceData {
  const WorkspaceData({
    required this.roles,
    required this.projects,
    required this.teams,
  });

  factory WorkspaceData.fromJson(Map<String, dynamic> json) => WorkspaceData(
    roles: _list(json['definitions'], (value) {
      final role = _object(value);
      return (
        id: _id(role['id']),
        name: _text(role['name']),
        role: _text(role['role']),
        description: _text(role['description']),
        systemPrompt: _text(role['systemPrompt']),
        skills: _list(role['skills'], _text),
      );
    }),
    projects: _list(json['projects'], (value) {
      final project = _object(value);
      return (
        id: _id(project['id']),
        name: _text(project['name']),
        description: _text(project['description']),
        repository: _nullableText(project['repository']),
        mainGithubAccountId: _nullableId(project['mainGithubAccountId']),
        brief: _text(project['brief']),
        repositoryContext: _text(project['repositoryContext']),
        files: _list(project['files'], parseWorkspaceFile),
        documents: _list(project['documents'], (value) {
          final document = _object(value);
          return (
            id: _id(document['id']),
            filename: _text(document['filename']),
            version: _integer(document['currentVersion']),
          );
        }),
        tasks: _list(project['tasks'], parseWorkspaceTask),
      );
    }),
    teams: _list(json['teams'], (value) {
      final team = _object(value);
      final updatedAt = _text(team['updatedAt']);
      if (DateTime.tryParse(updatedAt) == null) _invalidResponse();
      return (
        id: _id(team['id']),
        name: _text(team['name']),
        description: _text(team['description']),
        projectId: _nullableId(team['projectId']),
        updatedAt: updatedAt,
        members: _list(team['bots'], (value) {
          final membership = _object(value);
          final bot = _object(membership['bot']);
          final botId = _id(membership['botId']);
          if (botId != _id(bot['id'])) _invalidResponse();
          return (
            id: _id(membership['id']),
            botId: botId,
            parentId: _nullableId(membership['parentId']),
            definitionId: _nullableId(bot['definitionId']),
            name: _text(bot['name']),
            status: _code(bot['status'], {
              'IDLE',
              'RUNNING',
              'PAUSED',
              'ERROR',
            }),
            githubAccountId: _id(bot['githubAccountId']),
            schedule: bot['workSchedule'] == null
                ? null
                : parseWorkspaceSchedule(bot['workSchedule']),
            stages: _list(bot['stages'], (value) {
              final stage = _object(value);
              return (
                id: _id(stage['id']),
                title: _text(stage['title']),
                status: _text(stage['status']),
              );
            }),
          );
        }),
        tasks: _list(team['tasks'], parseWorkspaceTask),
      );
    }),
  );

  final List<WorkspaceRole> roles;
  final List<WorkspaceProject> projects;
  final List<WorkspaceTeam> teams;
}

WorkspaceSchedule parseWorkspaceSchedule(Object? value) {
  final schedule = _object(value);
  final days = _list(schedule['days'], _integer);
  final start = _text(schedule['startTime']);
  final end = _text(schedule['endTime']);
  final time = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$');
  if (days.isEmpty ||
      days.length > 7 ||
      days.toSet().length != days.length ||
      days.any((day) => day < 1 || day > 7) ||
      !time.hasMatch(start) ||
      !time.hasMatch(end) ||
      end.compareTo(start) <= 0) {
    _invalidResponse();
  }
  return (
    timezone: _id(schedule['timezone']),
    enabled: _boolean(schedule['enabled']),
    days: days,
    startTime: start,
    endTime: end,
  );
}

String requireCreatedId(Map<String, dynamic> response, String key) =>
    _id(_object(response[key])['id']);
List<WorkspaceAccount> parseWorkspaceAccounts(Map<String, dynamic> session) =>
    _list(session['githubAccounts'], (value) {
      final account = _object(value);
      return (
        id: _id(account['id']),
        login: _text(account['login']),
        scopes: _list(account['scopes'], _text),
        active:
            _code(account['status'], {
              'ACTIVE',
              'REAUTH_REQUIRED',
              'REVOKED',
            }) ==
            'ACTIVE',
      );
    });

Future<WorkspaceRepositoryPage> loadWorkspaceRepositoryPage(
  ApiClient api,
  String accountId, {
  int page = 1,
}) async {
  if (page < 1) {
    throw ArgumentError.value(page, 'page', 'Page must be positive');
  }
  final result = await api.request(
    '/github/accounts/${Uri.encodeComponent(accountId)}/repositories?page=$page',
  );
  if (!result.containsKey('nextPage')) _invalidResponse();
  final nextPage = result['nextPage'] == null
      ? null
      : _integer(result['nextPage']);
  if (nextPage != null && nextPage != page + 1) _invalidResponse();
  final repositories = _list<WorkspaceRepository>(result['repositories'], (
    value,
  ) {
    final repository = _object(value);
    return (
      id: _id(repository['id']),
      fullName: _text(repository['fullName']),
      canPush: _boolean(repository['canPush']),
    );
  });
  return (repositories: repositories, nextPage: nextPage);
}

final workspaceDataProvider = FutureProvider<WorkspaceData>(
  (ref) async => WorkspaceData.fromJson(
    await ref.watch(apiClientProvider).request('/workspace'),
  ),
  retry: (retryCount, error) => null,
);
