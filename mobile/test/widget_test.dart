import 'package:copilot_control_center/src/app_router.dart';
import 'package:copilot_control_center/src/core/api.dart';
import 'package:copilot_control_center/src/core/providers.dart';
import 'package:copilot_control_center/src/features/auth/login_page.dart';
import 'package:copilot_control_center/src/features/bots/bot_detail_page.dart';
import 'package:copilot_control_center/src/features/bots/create_bot_page.dart';
import 'package:copilot_control_center/src/features/dashboard/dashboard_page.dart';
import 'package:copilot_control_center/src/features/shell/app_shell.dart';
import 'package:copilot_control_center/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mobile navigation exposes every destination from the specification',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final router = createAppRouter(initialLocation: '/teams');
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            botsProvider.overrideWith((ref) async => []),
            projectsProvider.overrideWith((ref) async => []),
            teamsProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(appNavigationDestinations, hasLength(15));
      expect(find.text('Więcej'), findsOneWidget);
      expect(find.text('Zadania'), findsOneWidget);
      await tester.tap(find.byTooltip('Otwórz nawigację'));
      await tester.pumpAndSettle();
      for (final destination in appNavigationDestinations) {
        expect(find.text(destination.label), findsWidgets);
      }

      await tester.tap(find.text('Projekty i PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Nowy projekt'), findsOneWidget);
      expect(find.text('Nie ma jeszcze projektów'), findsOneWidget);
    },
  );

  testWidgets(
    'login screen offers local login and account registration before GitHub linking',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: LoginPage())),
      );
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
    },
  );

  testWidgets(
    'projects screen displays the pinned progress scan and scan action',
    (tester) async {
      final router = createAppRouter(initialLocation: '/projects');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith(
              (ref) async => [
                {
                  'id': 'project-1',
                  'name': 'Demo project',
                  'repository': 'owner/repo',
                  'description': '',
                  'documents': [],
                  'scans': [
                    {
                      'lifecycleStage': 'IMPLEMENTATION',
                      'summary': 'Commit abc123; one task in progress.',
                      'treeTruncated': false,
                    },
                  ],
                },
              ],
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Demo project'));
      await tester.pumpAndSettle();

      expect(find.text('Etap projektu: realizacja'), findsOneWidget);
      expect(find.text('Commit abc123; one task in progress.'), findsOneWidget);
      expect(find.text('Skanuj postęp projektu'), findsOneWidget);
    },
  );

  testWidgets('teams screen shows durable team members and available bots', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/teams');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          teamsProvider.overrideWith(
            (ref) async => [
              {
                'id': 'team-1',
                'name': 'Frontend',
                'description': 'Web app',
                'bots': [
                  {
                    'bot': {
                      'id': 'bot-1',
                      'name': 'Builder',
                      'repository': 'owner/repo',
                    },
                  },
                ],
              },
            ],
          ),
          botsProvider.overrideWith(
            (ref) async => [
              {'id': 'bot-1', 'name': 'Builder', 'repository': 'owner/repo'},
            ],
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Frontend'));
    await tester.pumpAndSettle();

    expect(find.text('1 botów przypisanych'), findsOneWidget);
    expect(find.text('Builder · owner/repo'), findsOneWidget);
    expect(find.text('Nowy zespół'), findsOneWidget);
  });

  testWidgets(
    'collaboration screen stores project notes without claiming resume',
    (tester) async {
      final router = createAppRouter(initialLocation: '/collaboration');
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            projectsProvider.overrideWith(
              (ref) async => [
                {'id': 'project-1', 'name': 'Portal'},
              ],
            ),
            projectCollaborationProvider('project-1').overrideWith(
              (ref) async => {
                'messages': [],
                'helpRequests': [],
                'checkpoints': [],
              },
            ),
          ],
          child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dziennik projektu'), findsOneWidget);
      expect(find.text('Prośby o pomoc'), findsOneWidget);
      expect(find.text('Ręczne checkpointy'), findsOneWidget);
      expect(find.textContaining('nie wznawiają zadania'), findsOneWidget);
    },
  );

  testWidgets('costs screen separates imported usage from subscriptions', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/costs');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          costsProvider.overrideWith(
            (ref) async => {
              'budget': {
                'monthlyLimitMinor': 5000,
                'currency': 'USD',
                'enforce': true,
              },
              'month': [
                {'category': 'USAGE', 'currency': 'USD', 'amountMinor': 1250},
                {'category': 'SUBSCRIPTION', 'currency': 'USD', 'amountMinor': 1000},
              ],
              'entries': [],
            },
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zużycie: 12.50 USD'), findsOneWidget);
    expect(find.text('Subskrypcje: 10.00 USD'), findsOneWidget);
    expect(find.text('Brak automatycznego źródła rozliczeń'), findsOneWidget);
  });

  testWidgets('project task board displays dependency status evidence', (
    tester,
  ) async {
    final router = createAppRouter(initialLocation: '/tasks');
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          botsProvider.overrideWith((ref) async => []),
          projectsProvider.overrideWith((ref) async => []),
          projectTasksProvider.overrideWith(
            (ref) async => [
              {
                'id': 'task-2',
                'title': 'Build screen',
                'status': 'TODO',
                'project': {'id': 'project-1', 'name': 'Portal'},
                'prerequisites': [
                  {
                    'dependsOn': {
                      'id': 'task-1',
                      'title': 'Create API',
                      'status': 'IN_PROGRESS',
                    },
                  },
                ],
              },
            ],
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zadania projektu i zależności'), findsOneWidget);
    expect(find.text('Build screen'), findsOneWidget);
    expect(find.textContaining('Create API'), findsOneWidget);
    expect(
      find.textContaining('oczekuje na ukończenie zależności'),
      findsOneWidget,
    );
  });

  testWidgets('dashboard shows API-driven empty state and navigation actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          botsProvider.overrideWith((ref) async => []),
          sessionDataProvider.overrideWith(
            (ref) async => {
              'user': {'displayName': 'Tester'},
              'githubAccounts': [],
            },
          ),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const DashboardPage()),
      ),
    );
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

  testWidgets(
    'bot creation wizard selects a writable repository before collecting task details',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionDataProvider.overrideWith(
              (ref) async => {
                'user': {'displayName': 'Tester'},
                'githubAccounts': [
                  {'id': 'gh-1', 'login': 'octocat', 'status': 'ACTIVE'},
                  {
                    'id': 'gh-2',
                    'login': 'octocat-old',
                    'status': 'REAUTH_REQUIRED',
                  },
                ],
              },
            ),
            apiClientProvider.overrideWith((ref) => _FakeBotSetupApi()),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const CreateBotPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stwórz swojego agenta'), findsOneWidget);
      expect(
        find.text('Które repozytorium ma obsługiwać bot?'),
        findsOneWidget,
      );
      expect(find.text('Opisz zadanie i zasady'), findsNothing);

      final nameField = find.byType(TextFormField).first;
      expect(tester.getSize(nameField).height, 58);
      await tester.enterText(nameField, 'Agent dokumentacji');
      expect(
        tester.widget<TextFormField>(nameField).controller!.text,
        'Agent dokumentacji',
      );
      expect(
        find.text('Połącz konto GitHub, aby wybrać repozytorium.'),
        findsNothing,
      );
      expect(find.text('@octocat'), findsOneWidget);
      expect(find.text('@octocat-old'), findsOneWidget);
      expect(find.text('aktywne'), findsOneWidget);
      expect(find.text('wymaga autoryzacji'), findsOneWidget);
      await tester.ensureVisible(find.text('@octocat'));
      await tester.tap(find.text('@octocat'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).first,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('octocat/docs · prywatne').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();

      expect(find.text('Opisz zadanie i zasady'), findsOneWidget);
      expect(find.text('Które repozytorium ma obsługiwać bot?'), findsNothing);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Zaktualizuj dokumentację.',
      );
      await tester.tap(find.text('Dalej'));
      await tester.pumpAndSettle();

      expect(find.text('Podziel pracę na etapy'), findsOneWidget);
      expect(find.text('octocat/docs'), findsOneWidget);
      expect(find.text('Utwórz bota'), findsOneWidget);
    },
  );

  testWidgets('an unstarted stage offers an explicit Copilot task action', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          botProvider.overrideWith(
            (ref, id) async => {
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
            },
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const BotDetailPage(botId: 'bot-test'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent dokumentacji'), findsOneWidget);
    expect(find.text('Aktualizacja README'), findsOneWidget);
    expect(find.text('Uruchom zadanie Copilot'), findsOneWidget);
    expect(find.textContaining('podglądowego GitHub REST API'), findsOneWidget);
    expect(find.text('Zatwierdź etap'), findsNothing);
  });

  testWidgets(
    'an unconfirmed Copilot submission shows Polish recovery instead of status polling',
    (tester) async {
      final api = _FakeUnconfirmedTaskApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            botProvider.overrideWith(
              (ref, id) async => {
                'name': 'Agent dokumentacji',
                'repository': 'example/docs',
                'systemPrompt': 'Działaj tylko w tym repozytorium.',
                'stages': [
                  {
                    'id': 'clstage00000000000000000000',
                    'number': 1,
                    'title': 'Logowanie',
                    'description': 'Popraw panel logowania.',
                    'acceptanceCriteria': ['Testy przechodzą'],
                    'status': 'RUNNING',
                    'submissionUnconfirmed': true,
                    'pullRequests': [],
                  },
                ],
              },
            ),
            apiClientProvider.overrideWith((ref) => api),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const BotDetailPage(botId: 'bot-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nie udało się potwierdzić'), findsOneWidget);
      expect(find.text('Sprawdź status Copilota'), findsNothing);
      await tester.ensureVisible(
        find.text('Sprawdziłem GitHub — ponów zadanie'),
      );
      await tester.tap(find.text('Sprawdziłem GitHub — ponów zadanie'));
      await tester.pumpAndSettle();
      expect(find.text('Sprawdź zadania GitHub'), findsOneWidget);
      expect(find.text('Nie ma zadania — ponów'), findsOneWidget);

      await tester.tap(find.text('Nie ma zadania — ponów'));
      await tester.pumpAndSettle();

      expect(api.confirmedNoTaskExists, isTrue);
    },
  );

  testWidgets(
    'a waiting stage blocks approval until review evidence is available',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            botProvider.overrideWith(
              (ref, id) async => {
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
              },
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const BotDetailPage(botId: 'bot-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Zatwierdź etap'), findsOneWidget);
      final approval = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Zatwierdź etap'),
      );
      expect(approval.onPressed, isNotNull);
      expect(find.text('Poproś o poprawki'), findsOneWidget);
      expect(
        find.text(
          'Akceptacja wymaga, by serwer potwierdził zielone CI oraz zaliczony test manualny dla aktualnego commita PR. Preview nie jest jeszcze wymuszane. Prośba o poprawki zapisuje uwagi; ponowne zadanie uruchomisz po ich sprawdzeniu.',
        ),
        findsOneWidget,
      );
    },
  );
}

class _FakeBotSetupApi extends ApiClient {
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    if (path == '/github/accounts/gh-1/repositories') {
      return {
        'repositories': [
          {
            'id': 'repo-1',
            'fullName': 'octocat/docs',
            'isPrivate': true,
            'canPush': true,
          },
          {
            'id': 'repo-2',
            'fullName': 'octocat/read-only',
            'isPrivate': false,
            'canPush': false,
          },
        ],
      };
    }

    throw StateError('Unexpected API request: $path');
  }
}

class _FakeUnconfirmedTaskApi extends ApiClient {
  bool? confirmedNoTaskExists;

  @override
  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool withCredentials = false,
  }) async {
    if (path == '/stages/clstage00000000000000000000/start' &&
        method == 'POST') {
      confirmedNoTaskExists =
          (data as Map<String, dynamic>)['confirmedNoTaskExists'] as bool?;
      return {
        'task': {'id': 'task-confirmed'},
      };
    }
    throw StateError('Unexpected API request: $path');
  }
}
