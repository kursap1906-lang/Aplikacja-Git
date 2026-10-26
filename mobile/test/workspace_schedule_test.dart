import 'dart:async';

import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/features/schedule/demo_schedule_page.dart';
import 'package:copilot_control_center/src/features/workspace/workspace_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _schedule = (
  timezone: 'Europe/Warsaw',
  enabled: true,
  days: [1, 7],
  startTime: '09:00',
  endTime: '17:00',
);

Widget _page({
  List<({String id, String name})> agents = const [
    (id: 'instance', name: 'Developer'),
  ],
  Map<String, WorkspaceSchedule> schedules = const {'instance': _schedule},
  required Future<void> Function(String, WorkspaceSchedule) onSave,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: BotSchedulePage(
        agents: agents,
        schedules: schedules,
        onSave: onSave,
      ),
    ),
  ),
);

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty real calendar has no sample bots or invented schedules', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      _page(
        agents: const [],
        schedules: const {},
        onSave: (_, _) async => saves++,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Brak instancji botów. Najpierw utwórz zespół.'),
      findsOneWidget,
    );
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(saves, 0);
  });

  testWidgets(
    'failed server save preserves edits without changing the persisted week overview',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(
        _page(
          onSave: (_, schedule) async {
            saves++;
            expect(schedule.days, [1, 2, 7]);
            throw const ApiException(
              'SERVER_UNAVAILABLE',
              'Schedule save failed.',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, 'Wtorek');
      await _tap(tester, 'Zapisz harmonogram');
      expect(find.text('Schedule save failed.'), findsOneWidget);
      expect(
        find.text('Developer · 09:00–17:00 · Europe/Warsaw'),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Wtorek'))
            .selected,
        isTrue,
      );
      expect(
        find.textContaining('Harmonogram zapisany na serwerze.'),
        findsNothing,
      );
      expect(saves, 1);
    },
  );

  testWidgets(
    'calendar validates empty weekdays and timezone before requesting save',
    (tester) async {
      var saves = 0;
      await tester.pumpWidget(_page(onSave: (_, _) async => saves++));
      await tester.pumpAndSettle();
      await _tap(tester, 'Poniedziałek');
      await _tap(tester, 'Niedziela');
      await _tap(tester, 'Zapisz harmonogram');
      expect(
        find.text('Wybierz co najmniej jeden dzień pracy.'),
        findsOneWidget,
      );
      await _tap(tester, 'Wtorek');
      await tester.enterText(
        find.widgetWithText(TextField, 'Strefa czasowa IANA'),
        '',
      );
      await _tap(tester, 'Zapisz harmonogram');
      expect(
        find.text('Podaj strefę czasową IANA, np. Europe/Warsaw.'),
        findsOneWidget,
      );
      expect(saves, 0);
    },
  );

  testWidgets(
    'save disables schedule edits and handles completion after disposal',
    (tester) async {
      final pending = Completer<void>();
      await tester.pumpWidget(_page(onSave: (_, _) => pending.future));
      await tester.pumpAndSettle();
      final button = find.text('Zapisz harmonogram');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Wtorek'))
            .onSelected,
        isNull,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      pending.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
