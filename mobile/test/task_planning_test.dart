import 'package:copilot_control_center/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ControlCenterApp());
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

  Future<void> select<T>(
    WidgetTester tester,
    String label,
    String value,
  ) async {
    final finder = find.byWidgetPredicate(
      (widget) =>
          widget is DropdownButtonFormField<T> &&
          widget.decoration.labelText == label,
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'wizard groups task drafts by bot and preserves priority and status',
    (tester) async {
      await open(tester);
      await tap(tester, 'Zespoły AI');
      await tap(tester, 'Utwórz zespół');
      await tap(tester, 'Zadanie');
      expect(find.text('Tech Lead (0)'), findsOneWidget);
      expect(find.text('Web Developer (0)'), findsOneWidget);
      await tap(tester, 'Dodaj task');
      await tester.enterText(input('Opis taska'), 'Zaprojektuj architekturę');
      await select<TaskPriority>(tester, 'Priorytet', 'Pilny');
      await select<String>(tester, 'Status taska', 'W trakcie');
      await tap(tester, 'Web Developer (0)');
      expect(find.text('Zaprojektuj architekturę'), findsNothing);
      await tap(tester, 'Dodaj task');
      await tester.enterText(input('Opis taska'), 'Zbuduj ekran');
      await select<TaskPriority>(tester, 'Priorytet', 'Wysoki');
      await tap(tester, 'Tech Lead (1)');
      expect(find.text('Zaprojektuj architekturę'), findsOneWidget);
      expect(find.text('Pilny'), findsOneWidget);
      expect(find.text('W trakcie'), findsOneWidget);
      await tap(tester, 'Zapis');
      await tap(tester, 'Zapisz zespół');
      expect(find.text('Tech Lead · W trakcie · Pilny'), findsOneWidget);
      expect(find.text('Web Developer · Oczekuje · Wysoki'), findsOneWidget);
      await tap(tester, 'Zadania zespołu');
      await tap(tester, 'Zaprojektuj architekturę');
      await select<TaskPriority>(tester, 'Priorytet', 'Niski');
      await tap(tester, 'Zapisz task');
      expect(find.text('Tech Lead · W trakcie · Niski'), findsOneWidget);
      await tap(tester, 'Przegląd');
      await tap(tester, 'Edytuj zespół');
      await tap(tester, 'Zadanie');
      expect(find.text('Niski'), findsOneWidget);
      await tap(tester, 'Web Developer (1)');
      expect(find.text('Zbuduj ekran'), findsOneWidget);
      expect(find.text('Wysoki'), findsOneWidget);
    },
  );

  testWidgets('removed bot tasks remain accessible and must be reassigned', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, 'Zespoły AI');
    await tap(tester, 'Utwórz zespół');
    await tap(tester, 'Zadanie');
    await tap(tester, 'Web Developer (0)');
    await tap(tester, 'Dodaj task');
    await tester.enterText(input('Opis taska'), 'Sprawdź frontend');
    await tap(tester, 'Boty');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Web Developer'));
    await tester.pumpAndSettle();
    await tap(tester, 'Zadanie');
    expect(find.text('Web Developer (1)'), findsNothing);
    await tap(tester, 'Taski bez bota');
    expect(find.text('Sprawdź frontend'), findsOneWidget);
    await tap(tester, 'Zapis');
    await tap(tester, 'Zapisz zespół');
    expect(
      find.text('Każdy task musi mieć opis i bota wybranego w zespole.'),
      findsOneWidget,
    );
    await tap(tester, 'Zadanie');
    await select<String>(tester, 'Bot odpowiedzialny', 'Backend Developer');
    expect(find.text('Backend Developer (1)'), findsOneWidget);
    await tap(tester, 'Zapis');
    await tap(tester, 'Zapisz zespół');
    expect(
      find.text('Backend Developer · Oczekuje · Normalny'),
      findsOneWidget,
    );
  });

  testWidgets(
    'repository scan is explicit placeholder and shares manual context with chosen bots only',
    (tester) async {
      await open(tester);
      await tap(tester, 'Asystent Budowlańca');
      await tap(tester, 'Profil projektu');
      await tap(tester, 'Skanuj repozytorium z AI');
      expect(
        find.text('Skanowanie repozytorium nie jest skonfigurowane'),
        findsOneWidget,
      );
      expect(find.textContaining('Skan nie został wykonany.'), findsOneWidget);
      await tap(tester, 'Rozumiem');
      await tap(tester, 'Przekaż kontekst botom');
      expect(
        find.text('Najpierw wpisz kontekst repozytorium dla botów.'),
        findsOneWidget,
      );
      await tester.enterText(
        input('Kontekst repozytorium dla botów'),
        'Flutter, API w src/, testy: flutter test.',
      );
      await tap(tester, 'Przekaż kontekst botom');
      await tap(tester, 'Anuluj');
      await tap(tester, 'Przegląd');
      await tap(tester, 'Tech Lead');
      expect(
        find.textContaining('Kontekst projektu: Asystent Budowlańca'),
        findsNothing,
      );
      await tap(tester, 'Pulpit');
      await tap(tester, 'Asystent Budowlańca');
      await tap(tester, 'Profil projektu');
      expect(
        find.text('Flutter, API w src/, testy: flutter test.'),
        findsOneWidget,
      );
      await tap(tester, 'Przekaż kontekst botom');
      for (final name in [
        'Tech Lead',
        'Backend Developer',
        'Mobile Developer',
        'CAD Engineer',
        '3D Artist',
        '2D Designer',
      ]) {
        await tester.tap(find.widgetWithText(CheckboxListTile, name));
        await tester.pump();
      }
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Web Developer'));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Dodaj do czatów lokalnych'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Web Developer'));
      await tester.pump();
      await tap(tester, 'Dodaj do czatów lokalnych');
      await tap(tester, 'Przegląd');
      await tap(tester, 'Web Developer');
      expect(
        find.textContaining('Kontekst projektu: Asystent Budowlańca'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Flutter, API w src/, testy: flutter test.'),
        findsOneWidget,
      );
      await tap(tester, 'Pulpit');
      await tap(tester, 'Asystent Budowlańca');
      await tap(tester, 'Tech Lead');
      expect(
        find.textContaining('Kontekst projektu: Asystent Budowlańca'),
        findsNothing,
      );
    },
  );
}
