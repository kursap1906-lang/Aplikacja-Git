import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_costs_page.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _metadata({String status = 'READY'}) => {
  'status': status,
  'fetchedAt': status == 'READY' ? '2026-10-26T19:00:00Z' : null,
  'autoAvailable': status == 'READY' ? true : null,
  'errorMessage': null,
  'quota': status == 'READY'
      ? {
          'quotaSnapshots': {
            'ai_credits': {
              'isUnlimitedEntitlement': false,
              'entitlementRequests': 1000,
              'usedRequests': 123.5,
              'remainingPercentage': 87.65,
              'overage': 0,
              'overageAllowedWithExhaustedQuota': false,
              'resetDate': '2026-11-01',
            },
          },
        }
      : null,
};

Map<String, dynamic> _response({
  Map<String, dynamic>? policy,
  Map<String, dynamic>? metadata,
  bool enabled = true,
}) => {
  'sdk': {
    'model': 'auto',
    'currency': 'USD',
    'executionAvailable': false,
    'providerBudgetManagedByApplication': false,
    'metadataEnabled': enabled,
    'policy': policy,
    'accounts': [
      {
        'id': 'account',
        'login': 'actual-fixture-account',
        'status': 'ACTIVE',
        'metadata': metadata,
      },
    ],
  },
  'openai': {
    'currency': 'USD',
    'month': '2026-10',
    'model': 'fixture-analysis-model',
    'maximumAnalysisCostMicros': 1000000,
    'globalMonthlyBudgetMicros': 10000000,
    'spentMicros': 1117,
    'reservedMicros': 1000000,
    'unknownCount': 1,
    'recent': <Map<String, dynamic>>[
      {
        'kind': 'DIAGNOSTIC',
        'status': 'COMPLETED',
        'estimatedCostMicros': 1117,
      },
      {'kind': 'TEAM_TASKS', 'status': 'UNKNOWN', 'estimatedCostMicros': null},
    ],
  },
};

class _CostsApi extends ApiClient {
  Map<String, dynamic>? policy;
  Map<String, dynamic>? metadata = _metadata();
  bool enabled = true;
  bool completePoll = false;
  final saved = <Map<String, dynamic>>[];
  ApiException? loadError;
  int requests = 0;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    requests++;
    if (path == '/workspace/costs') {
      if (loadError != null) throw loadError!;
      if (completePoll && metadata?['status'] == 'QUEUED') {
        metadata = _metadata();
      }
      return _response(policy: policy, metadata: metadata, enabled: enabled);
    }
    if (path == '/workspace/costs/sdk-policy') {
      expect(method, 'POST');
      final body = Map<String, dynamic>.from(data! as Map);
      saved.add(body);
      if (body['updatedAt'] != policy?['updatedAt']) {
        throw const ApiException(
          'SDK_COST_POLICY_CHANGED',
          'Synthetic conflict',
        );
      }
      policy = {
        'monthlyExtraLimitMinor': body['monthlyExtraLimitMinor'],
        'updatedAt':
            '2026-10-26T19:01:${saved.length.toString().padLeft(2, '0')}Z',
      };
      return {'policy': policy};
    }
    expect(path, '/workspace/github-accounts/account/sdk-metadata');
    expect(method, 'POST');
    metadata = _metadata(status: 'QUEUED');
    return {'status': 'QUEUED', 'requestedAt': '2026-10-26T19:02:00Z'};
  }
}

Future<void> _mount(WidgetTester tester, _CostsApi api) async {
  await tester.binding.setSurfaceSize(const Size(1400, 2000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: WorkspaceCostsPage(api: api)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'SDK policy conflicts reach the UI with an actionable localized message',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final dio = Dio(
        BaseOptions(baseUrl: 'https://workspace.example.test/api'),
      );
      final api = ApiClient(dio: dio);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 409,
                  data: {
                    'error': {'code': 'SDK_COST_POLICY_CHANGED'},
                  },
                ),
              ),
            );
          },
        ),
      );
      try {
        await expectLater(
          api.request(
            '/workspace/costs/sdk-policy',
            method: 'POST',
            data: {'monthlyExtraLimitMinor': 100, 'updatedAt': null},
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('Wczytaj zapisany limit'),
            ),
          ),
        );
      } finally {
        dio.close(force: true);
      }
    },
  );

  testWidgets(
    'costs show actual provider quotas, native Auto and separate OpenAI usage; saves exact cents',
    (tester) async {
      final api = _CostsApi();
      await _mount(tester, api);
      expect(find.textContaining('natywnego trybu Auto'), findsOneWidget);
      expect(find.textContaining('wykorzystano: 123.5'), findsOneWidget);
      expect(
        find.textContaining('Twoje rozliczone analizy: 0.001117 USD'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Niepotwierdzone rozliczenia: 1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Nie zapisano jeszcze polityki'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '12,34');
      await tester.tap(find.text('Zapisz limit SDK'));
      await tester.pumpAndSettle();
      expect(api.saved.single, {
        'monthlyExtraLimitMinor': 1234,
        'updatedAt': null,
      });
      expect(
        find.text('Zapisano limit dodatkowych wydatków GitHub Copilot.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12.34',
      );
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('Zapisz limit SDK'));
      await tester.pumpAndSettle();
      expect(api.saved.last['monthlyExtraLimitMinor'], 0);
      expect(api.saved.last['updatedAt'], isNotNull);
    },
  );

  testWidgets(
    'failed saves and background refresh preserve draft and stale version until explicit reload',
    (tester) async {
      final api = _CostsApi()
        ..policy = {
          'monthlyExtraLimitMinor': 1000,
          'updatedAt': '2026-10-26T19:00:00Z',
        };
      await _mount(tester, api);
      await tester.enterText(find.byType(TextField), '25,50');
      api.policy = {
        'monthlyExtraLimitMinor': 2000,
        'updatedAt': '2026-10-26T19:01:00Z',
      };
      await tester.tap(find.byTooltip('Odśwież koszty'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '25,50',
      );
      api.loadError = const ApiException(
        'NETWORK_ERROR',
        'Synthetic load failure',
      );
      await tester.tap(find.text('Wczytaj zapisany limit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wczytaj'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic load failure'), findsOneWidget);
      api.loadError = null;
      await tester.tap(find.byTooltip('Odśwież koszty'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '25,50',
      );
      await tester.tap(find.text('Zapisz limit SDK'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Synthetic conflict'), findsOneWidget);
      expect(api.saved.single['updatedAt'], '2026-10-26T19:00:00Z');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '25,50',
      );
      await tester.tap(find.text('Wczytaj zapisany limit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '25,50',
      );
      await tester.tap(find.text('Wczytaj zapisany limit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wczytaj'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '20.00',
      );
    },
  );

  testWidgets(
    'unknown quota is not zero; refresh polls actual metadata and retains edited policy',
    (tester) async {
      final api = _CostsApi()..metadata = null;
      await _mount(tester, api);
      expect(find.text('Nie pobrano jeszcze danych pakietu.'), findsOneWidget);
      expect(find.textContaining('wykorzystano:'), findsNothing);
      await tester.enterText(find.byType(TextField), '8.50');
      await tester.tap(find.text('Pobierz pakiet z GitHub'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Trwa odczyt metadanych GitHub…'), findsOneWidget);
      api.completePoll = true;
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.textContaining('wykorzystano: 123.5'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '8.50',
      );
      await tester.pumpWidget(const SizedBox());
      final reads = api.requests;
      await tester.pump(const Duration(seconds: 10));
      expect(api.requests, reads);
    },
  );

  testWidgets(
    'disabled metadata remains honest and malformed money never reaches API',
    (tester) async {
      final api = _CostsApi()..enabled = false;
      await _mount(tester, api);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Pobierz pakiet z GitHub'),
            )
            .onPressed,
        isNull,
      );
      for (final invalid in ['-1', '1.234', '10000.01']) {
        await tester.enterText(find.byType(TextField), invalid);
        await tester.tap(find.text('Zapisz limit SDK'));
        await tester.pumpAndSettle();
      }
      expect(api.saved, isEmpty);
    },
  );

  test('cost DTO rejects false currencies, non-Auto models, absent quota numbers and fabricated known costs', () {
    final values = [
      (() {
        final value = _response();
        value['sdk']['model'] = 'fixed-model';
        return value;
      })(),
      (() {
        final value = _response();
        value['sdk']['currency'] = 'PLN';
        return value;
      })(),
      (() {
        final value = _response(metadata: _metadata());
        value['sdk']['accounts'][0]['metadata']['quota']['quotaSnapshots']['ai_credits']
            .remove('usedRequests');
        return value;
      })(),
      (() {
        final value = _response();
        value['openai']['recent'][1]['estimatedCostMicros'] = 0;
        return value;
      })(),
    ];
    for (final value in values) {
      expect(() => parseWorkspaceCosts(value), throwsA(isA<ApiException>()));
    }
  });
}
