import 'package:copilot_control_center/src/core/providers.dart';
import 'package:copilot_control_center/src/features/bots/bot_detail_page.dart';
import 'package:copilot_control_center/src/features/dashboard/dashboard_page.dart';
import 'package:copilot_control_center/src/features/auth/login_page.dart';
import 'package:copilot_control_center/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('login screen offers local login and account registration before GitHub linking', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginPage())));
    await tester.pumpAndSettle();

    expect(find.text('Logowanie'), findsWidgets);
    expect(find.text('Rejestracja'), findsOneWidget);
    expect(find.text('Adres e-mail'), findsOneWidget);
    expect(find.text('Zaloguj się'), findsOneWidget);

    await tester.tap(find.text('Rejestracja'));
    await tester.pumpAndSettle();

    expect(find.text('Nazwa użytkownika'), findsOneWidget);
    expect(find.text('Powtórz hasło'), findsOneWidget);
    expect(find.text('Utwórz konto'), findsOneWidget);
    expect(find.text('Kontynuuj przez GitHub'), findsNothing);
  });

  testWidgets('dashboard shows API-driven empty state and navigation actions', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        botsProvider.overrideWith((ref) async => []),
        sessionDataProvider.overrideWith((ref) async => {
          'user': {'displayName': 'Tester'},
          'githubAccounts': [],
        }),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const DashboardPage()),
    ));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nie masz jeszcze botów.'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Dzień dobry, Tester.'), findsOneWidget);
    expect(find.text('Nie masz jeszcze botów.'), findsOneWidget);
    expect(find.text('Połącz GitHub'), findsOneWidget);
  });

  testWidgets('an unstarted stage is not presented as a running Copilot task', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        botProvider.overrideWith((ref, id) async => {
          'name': 'Agent dokumentacji',
          'repository': 'example/docs',
          'systemPrompt': 'Działaj tylko w tym repozytorium.',
          'stages': [
            {
              'id': 'clstage00000000000000000000',
              'number': 1,
              'title': 'Aktualizacja README',
              'description': 'Popraw dokumentację.',
              'acceptanceCriteria': ['Testy przechodzą'],
              'status': 'PENDING',
              'pullRequests': [],
            },
          ],
        }),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const BotDetailPage(botId: 'bot-test')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Agent dokumentacji'), findsOneWidget);
    expect(find.text('Aktualizacja README'), findsOneWidget);
    expect(find.text('Uruchamianie przez Copilot niedostępne'), findsOneWidget);
    expect(find.text('Zatwierdź etap'), findsNothing);
  });

  testWidgets('a waiting stage exposes explicit approval and separate change requests', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        botProvider.overrideWith((ref, id) async => {
          'name': 'Agent dokumentacji',
          'repository': 'example/docs',
          'systemPrompt': 'Działaj tylko w tym repozytorium.',
          'stages': [
            {
              'id': 'clstage00000000000000000000',
              'number': 1,
              'title': 'Aktualizacja README',
              'description': 'Gotowe do weryfikacji.',
              'acceptanceCriteria': ['Testy przechodzą'],
              'status': 'WAITING_APPROVAL',
              'pullRequests': [],
            },
          ],
        }),
      ],
      child: MaterialApp(theme: AppTheme.dark, home: const BotDetailPage(botId: 'bot-test')),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Zatwierdź etap'), findsOneWidget);
    expect(find.text('Poproś o poprawki'), findsOneWidget);
    expect(find.text('Akceptacja etapu nie scala pull requesta i nie uruchamia agenta.'), findsOneWidget);
  });
}
