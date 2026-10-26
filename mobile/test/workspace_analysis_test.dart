import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_analysis.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _job({
  String status = 'QUEUED',
  String requestKey = 'fixture-request',
}) {
  final pending = {'QUEUED', 'RUNNING', 'UNKNOWN'}.contains(status);
  return {
    'id': 'analysis',
    'teamId': 'team',
    'kind': 'TEAM_TASKS',
    'requestKey': requestKey,
    'status': status,
    'model': 'fixture-model',
    'estimatedCostMicros': pending ? null : 1583,
    'reservationHeldMicros': pending ? 1000000 : 0,
    'errorMessage': status == 'UNKNOWN' || status == 'FAILED'
        ? 'Provider response unconfirmed'
        : null,
    'result': status == 'COMPLETED'
        ? {
            'summary': 'Persisted plan',
            'taskIds': ['task'],
            'addedTaskCount': 1,
          }
        : null,
  };
}

class _AnalysisApi extends ApiClient {
  bool enabled = true;
  bool loseFirstResponse = false;
  bool unconfirmed = false;
  bool completeOnPoll = true;
  Map<String, dynamic>? job;
  final keys = <String>[];
  int reads = 0;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    expect(path, '/workspace/teams/team/analyses');
    if (method == 'POST') {
      final key = (data! as Map<String, dynamic>)['requestKey'] as String;
      keys.add(key);
      job ??= _job(requestKey: key);
      if (loseFirstResponse && keys.length == 1) {
        throw const ApiException('NETWORK_ERROR', 'Synthetic lost response');
      }
      return {'analysis': job};
    }
    reads++;
    if (job != null && (completeOnPoll || unconfirmed)) {
      job = _job(
        requestKey: job!['requestKey'] as String,
        status: unconfirmed ? 'UNKNOWN' : 'COMPLETED',
      );
    }
    return {
      'enabled': enabled,
      'model': 'fixture-model',
      'maximumCostMicros': 1000000,
      'monthlyBudgetMicros': 10000000,
      'analyses': [if (job != null) job],
    };
  }
}

Future<void> _open(
  WidgetTester tester,
  _AnalysisApi api, {
  required VoidCallback onChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showWorkspaceAnalysis(
              context,
              api: api,
              teamId: 'team',
              onChanged: onChanged,
            ),
            child: const Text('Open analysis'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open analysis'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'analysis requires confirmation, polls persistent result and refreshes tasks',
    (tester) async {
      final api = _AnalysisApi();
      var changes = 0;
      await _open(tester, api, onChanged: () => changes++);
      expect(api.keys, isEmpty);
      expect(find.textContaining('bez startu botów'), findsOneWidget);
      expect(find.textContaining('1 USD'), findsOneWidget);
      await tester.tap(find.text('Analizuj i dodaj taski'));
      await tester.pump();
      await tester.pump();
      expect(api.keys, hasLength(1));
      expect(
        api.keys.single,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(find.text('Oczekuje w kolejce'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('Persisted plan'), findsOneWidget);
      expect(find.text('Dodano tasków: 1'), findsOneWidget);
      expect(find.textContaining('0.001583 USD'), findsOneWidget);
      expect(changes, 1);
      await tester.tap(find.text('Odśwież historię'));
      await tester.pumpAndSettle();
      expect(changes, 1);
      await tester.tap(find.text('Zamknij'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'lost POST response keeps the same idempotency key on manual confirmation retry',
    (tester) async {
      final api = _AnalysisApi()
        ..loseFirstResponse = true
        ..completeOnPoll = false;
      await _open(tester, api, onChanged: () {});
      await tester.tap(find.text('Analizuj i dodaj taski'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic lost response'), findsOneWidget);
      await tester.tap(find.text('Ponów potwierdzenie'));
      await tester.pump();
      await tester.pump();
      expect(api.keys, hasLength(2));
      expect(api.keys[1], api.keys[0]);
      await tester.tap(find.text('Zamknij'));
      await tester.pumpAndSettle();
      final reads = api.reads;
      await tester.pump(const Duration(seconds: 10));
      expect(api.reads, reads);
    },
  );

  testWidgets(
    'unknown billing retains the reservation without automatic retry or fabricated cost',
    (tester) async {
      final api = _AnalysisApi()
        ..unconfirmed = true
        ..job = _job(status: 'UNKNOWN');
      await _open(tester, api, onChanged: () {});
      expect(find.text('Nie potwierdzono rozliczenia'), findsOneWidget);
      expect(
        find.textContaining('Zarezerwowany limit: 1.00 USD'),
        findsOneWidget,
      );
      expect(find.textContaining('Szacowany koszt modelu:'), findsNothing);
      await tester.pump(const Duration(seconds: 10));
      expect(api.keys, isEmpty);
      expect(api.reads, 1);
    },
  );

  testWidgets('disabled backend cannot start a paid analysis', (tester) async {
    final api = _AnalysisApi()..enabled = false;
    await _open(tester, api, onChanged: () {});
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Analizuj i dodaj taski'),
    );
    expect(button.onPressed, isNull);
    expect(api.keys, isEmpty);
  });

  test('analysis DTO rejects another team, inconsistent charges and mismatched task counts', () {
    for (final job in [
      {..._job(), 'teamId': 'another-team'},
      {..._job(status: 'UNKNOWN'), 'estimatedCostMicros': 0},
      {..._job(status: 'COMPLETED'), 'reservationHeldMicros': 1000000},
      {..._job(status: 'COMPLETED'), 'estimatedCostMicros': 1000001},
      {
        ..._job(status: 'COMPLETED'),
        'result': {
          'summary': 'Invalid',
          'taskIds': ['task'],
          'addedTaskCount': 2,
        },
      },
    ]) {
      expect(
        () => parseWorkspaceAnalysis(job, teamId: 'team'),
        throwsA(isA<ApiException>()),
      );
    }
  });
}
