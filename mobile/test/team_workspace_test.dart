import 'package:copilot_control_center/main.dart';
import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/workspace/demo_collaboration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LogoutClient extends ApiClient {
  ApiException? error;
  bool cleared = false;
  String? requestedPath;
  String? requestedMethod;
  bool credentials = false;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    requestedPath = path;
    requestedMethod = method;
    credentials = withCredentials;
    if (error != null) throw error!;
    return {'ok': true};
  }

  @override
  Future<void> forgetSession() async => cleared = true;
}

void main() {
  Future<void> open(
    WidgetTester tester, {
    Future<void> Function()? logout,
  }) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ControlCenterApp(logout: logout));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  Future<void> select(WidgetTester tester, String label, String value) async {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<String> &&
          widget.decoration.labelText == label,
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'navigation removes global tasks, collaboration and team creation',
    (tester) async {
      await open(tester);
      expect(find.widgetWithText(ListTile, 'Zadania'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Współpraca'), findsNothing);
      expect(find.text('Nowy zespół'), findsNothing);
      expect(find.text('Utwórz zespół'), findsNothing);
      await tap(tester, 'Zespoły AI');
      expect(find.text('Utwórz zespół'), findsOneWidget);
      await tap(tester, 'Kalendarz');
      expect(find.text('Utwórz zespół'), findsNothing);
      expect(find.text('Godziny pracy'), findsOneWidget);
    },
  );

  testWidgets(
    'custom bot validates fields and becomes available across the app',
    (tester) async {
      await open(tester);
      await tap(tester, 'Boty i role');
      await tap(tester, 'Dodaj własnego bota');
      await tap(tester, 'Utwórz bota');
      expect(find.text('Podaj nazwę bota.'), findsOneWidget);
      expect(find.text('Podaj rolę bota.'), findsOneWidget);
      await tester.enterText(input('Nazwa bota'), 'Tech Lead');
      await tester.enterText(input('Rola i specjalizacja'), 'Testy wydajności');
      await tap(tester, 'Utwórz bota');
      expect(find.text('Bot o tej nazwie już istnieje.'), findsOneWidget);
      await tester.enterText(input('Nazwa bota'), 'Mój tester');
      await tester.enterText(input('Opis obowiązków'), 'Sprawdzaj regresje.');
      await tap(tester, 'Utwórz bota');
      expect(find.text('Mój tester'), findsWidgets);
      await tap(tester, 'Kalendarz');
      await select(tester, 'Bot', 'Mój tester');
      await tap(tester, 'Zapisz harmonogram');
      expect(find.text('Mój tester · 09:00–17:00'), findsNWidgets(5));
      await tap(tester, 'Zespoły AI');
      await tap(tester, 'Utwórz zespół');
      await tap(tester, 'Boty');
      final checkbox = find.widgetWithText(CheckboxListTile, 'Mój tester');
      await tester.ensureVisible(checkbox);
      await tester.tap(checkbox);
      await tester.pumpAndSettle();
      await tap(tester, 'Zapis');
      await tap(tester, 'Zapisz zespół');
      expect(find.text('Mój tester'), findsOneWidget);
      await tap(tester, 'Współpraca');
      expect(find.text('Mój tester'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('project opens task details without launching the team wizard', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Projekty i PDF');
    await tap(tester, 'Asystent Budowlańca');
    expect(find.text('Szczegóły zadania'), findsOneWidget);
    expect(find.text('Opis i materiały zadania'), findsOneWidget);
    expect(find.text('Postęp zadania'), findsOneWidget);
    expect(find.text('Podgląd belki 3D'), findsOneWidget);
    expect(find.text('Edytuj zespół AI'), findsNothing);
    expect(find.text('Nazwa zespołu'), findsNothing);
    await tap(tester, 'Lista projektów');
    expect(find.text('Specyfikacje PDF i etapy'), findsOneWidget);
  });

  testWidgets(
    'team overview contains tasks with editing, assignment and status',
    (tester) async {
      await open(tester);
      await tap(tester, 'Asystent Budowlańca');
      expect(find.text('Podgląd belki 3D'), findsOneWidget);
      await tap(tester, 'Zadania zespołu');
      await tap(tester, 'Dodaj task zespołu');
      await tap(tester, 'Zapisz task');
      expect(find.text('Wpisz opis taska.'), findsOneWidget);
      await tester.enterText(input('Opis taska'), 'Test nowego ekranu');
      await select(tester, 'Bot odpowiedzialny', 'Web Developer');
      await select(tester, 'Status taska', 'W trakcie');
      await tap(tester, 'Zapisz task');
      expect(find.text('Test nowego ekranu'), findsOneWidget);
      expect(find.text('Web Developer · W trakcie · Normalny'), findsOneWidget);
      await tap(tester, 'Test nowego ekranu');
      await select(tester, 'Status taska', 'Gotowe');
      await tap(tester, 'Zapisz task');
      expect(find.text('Web Developer · Gotowe · Normalny'), findsOneWidget);
      await tap(tester, 'Test nowego ekranu');
      await tap(tester, 'Anuluj');
      expect(find.text('Test nowego ekranu'), findsOneWidget);
      await tap(tester, 'Projekty i PDF');
      await tap(tester, 'Asystent Budowlańca');
      expect(find.text('Test nowego ekranu'), findsOneWidget);
    },
  );

  testWidgets('team graph saves hierarchy and blocks cyclic supervisors', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Asystent Budowlańca');
    await tap(tester, 'Współpraca');
    expect(find.text('Graf współpracy'), findsOneWidget);
    await tap(tester, 'Web Developer');
    await select(tester, 'Raportuje do', 'Backend Developer');
    await tap(tester, 'Zapisz relację');
    expect(
      tester
          .widget<DemoCollaboration>(find.byType(DemoCollaboration))
          .parents['web'],
      'backend',
    );
    await tap(tester, 'Backend Developer');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    final dialog = find.byType(Dialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Web Developer')),
      findsNothing,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tap(tester, 'Anuluj');
    await tap(tester, 'Pulpit');
    await tap(tester, 'Asystent Budowlańca');
    await tap(tester, 'Współpraca');
    expect(
      tester
          .widget<DemoCollaboration>(find.byType(DemoCollaboration))
          .parents['web'],
      'backend',
    );
    await tap(tester, 'Tech Lead');
    final supervisor = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(supervisor.items, hasLength(1));
    await tap(tester, 'Anuluj');
  });

  testWidgets('logout ends the workspace and a reopened demo is fresh', (
    tester,
  ) async {
    var calls = 0;
    await open(
      tester,
      logout: () async {
        calls++;
      },
    );
    await tester.tap(find.byTooltip('Wyloguj'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Wylogowano'), findsOneWidget);
    expect(find.text('AI Workspace'), findsNothing);
    await tap(tester, 'Otwórz demonstrację');
    expect(find.text('AI Workspace'), findsOneWidget);
  });

  testWidgets(
    'logout failure leaves the workspace accessible and shows an error',
    (tester) async {
      await open(
        tester,
        logout: () async {
          throw const ApiException('NETWORK_ERROR', 'Brak połączenia', 503);
        },
      );
      await tester.tap(find.byTooltip('Wyloguj'));
      await tester.pumpAndSettle();
      expect(find.text('Wylogowano'), findsNothing);
      expect(find.textContaining('Nie udało się wylogować:'), findsOneWidget);
      expect(find.text('AI Workspace'), findsOneWidget);
    },
  );

  testWidgets('hierarchy editor scrolls at phone width and cancels changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var parents = <String, String>{'web': 'lead', 'backend': 'lead'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, update) => DemoCollaboration(
                members: const [
                  (id: 'lead', name: 'Lead', role: 'Koordynacja'),
                  (id: 'web', name: 'Web', role: 'Frontend'),
                  (id: 'backend', name: 'Backend', role: 'API'),
                ],
                parents: parents,
                onChanged: (value) => update(() => parents = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tap(tester, 'Web');
    await select(tester, 'Raportuje do', 'Backend');
    await tap(tester, 'Anuluj');
    expect(parents['web'], 'lead');
    expect(tester.takeException(), isNull);
  });

  test(
    'logout revokes server session before clearing saved credentials',
    () async {
      final api = _LogoutClient();
      await api.signOut();
      expect(api.requestedPath, '/auth/logout');
      expect(api.requestedMethod, 'POST');
      expect(api.credentials, isTrue);
      expect(api.cleared, isTrue);
    },
  );

  test('logout tolerates expired sessions but not server errors', () async {
    final api = _LogoutClient()
      ..error = const ApiException('UNAUTHENTICATED', 'Expired', 401);
    await api.signOut();
    expect(api.cleared, isTrue);
    api
      ..cleared = false
      ..error = const ApiException('SERVER_UNAVAILABLE', 'Unavailable', 503);
    await expectLater(api.signOut(), throwsA(isA<ApiException>()));
    expect(api.cleared, isFalse);
  });
}
