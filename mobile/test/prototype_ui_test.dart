import 'package:copilot_control_center/main.dart';
import 'package:copilot_control_center/src/features/schedule/demo_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ControlCenterApp());
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final target = find.text(text).first;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('settings is the last navigation destination', (tester) async {
    await openApp(tester);
    final calendar = find.widgetWithText(ListTile, 'Kalendarz');
    final settings = find.widgetWithText(ListTile, 'Ustawienia');
    expect(
      tester.getTopLeft(settings).dy,
      greaterThan(tester.getTopLeft(calendar).dy),
    );
    await tapText(tester, 'Ustawienia');
    expect(find.text('Integracje'), findsWidgets);
    await tapText(tester, 'Kalendarz');
    expect(find.text('Godziny pracy'), findsOneWidget);
  });

  testWidgets(
    'revision instructions are required and cancel preserves approval',
    (tester) async {
      await openApp(tester);
      await tapText(tester, 'Do poprawek');
      await tapText(tester, 'Przekaż do poprawek');
      expect(find.text('Wpisz, co zespół musi poprawić.'), findsOneWidget);
      await tapText(tester, 'Anuluj');
      expect(find.text('Zatwierdź'), findsNWidgets(2));
      await tapText(tester, 'Do poprawek');
      await tester.enterText(
        find.byType(TextFormField),
        '  Dodaj testy geometrii.  ',
      );
      await tapText(tester, 'Przekaż do poprawek');
      expect(find.text('Dodaj testy geometrii.'), findsOneWidget);
      expect(find.text('Do poprawek · Podgląd CAD i 3D'), findsOneWidget);
      expect(find.text('Zatwierdź'), findsOneWidget);
      await tapText(tester, 'Asystent Budowlańca');
      expect(find.text('Uwagi do poprawek'), findsOneWidget);
      expect(find.text('Dodaj testy geometrii.'), findsOneWidget);
      expect(find.text('Wymaga Twojej akceptacji'), findsNothing);
    },
  );

  testWidgets('team detail also requires revision feedback', (tester) async {
    await openApp(tester);
    await tapText(tester, 'Asystent Budowlańca');
    await tapText(tester, 'Do poprawek');
    await tester.enterText(find.byType(TextFormField), 'Popraw podgląd CAD.');
    await tapText(tester, 'Przekaż do poprawek');
    expect(find.text('Popraw podgląd CAD.'), findsOneWidget);
    expect(find.text('Wymaga Twojej akceptacji'), findsNothing);
  });

  testWidgets('calendar validates weekdays, saves, and survives navigation', (
    tester,
  ) async {
    await openApp(tester);
    await tapText(tester, 'Kalendarz');
    expect(find.text('Godziny pracy'), findsOneWidget);
    for (final day in [
      'Poniedziałek',
      'Wtorek',
      'Środa',
      'Czwartek',
      'Piątek',
    ]) {
      await tester.tap(find.widgetWithText(FilterChip, day));
      await tester.pump();
    }
    await tapText(tester, 'Zapisz harmonogram');
    expect(find.text('Wybierz co najmniej jeden dzień pracy.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, 'Poniedziałek'));
    await tapText(tester, 'Zapisz harmonogram');
    expect(find.text('Tech Lead · 09:00–17:00'), findsOneWidget);
    await tapText(tester, 'Pulpit');
    await tapText(tester, 'Kalendarz');
    expect(find.text('Tech Lead · 09:00–17:00'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tapText(tester, 'Zapisz harmonogram');
    expect(find.text('Tech Lead · 09:00–17:00'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('calendar rejects reversed hours and isolates bot schedules', (
    tester,
  ) async {
    await openApp(tester);
    await tapText(tester, 'Kalendarz');
    await tapText(tester, 'Koniec: 17:00');
    await tester.tap(find.byIcon(Icons.keyboard_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '08');
    await tester.enterText(find.byType(TextField).last, '00');
    await tapText(tester, 'OK');
    await tapText(tester, 'Zapisz harmonogram');
    expect(
      find.text('Koniec musi być późniejszy niż początek w tym samym dniu.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Web Developer').last);
    await tester.pumpAndSettle();
    expect(find.text('Koniec: 17:00'), findsOneWidget);
    await tapText(tester, 'Zapisz harmonogram');
    expect(find.text('Web Developer · 09:00–17:00'), findsNWidgets(5));
    expect(find.text('Tech Lead · 09:00–08:00'), findsNothing);
  });

  testWidgets('calendar form works at phone width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DemoSchedulePage(agents: [(id: 'lead', name: 'Tech Lead')]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapText(tester, 'Zapisz harmonogram');
    expect(find.text('Tech Lead · 09:00–17:00'), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });
}
