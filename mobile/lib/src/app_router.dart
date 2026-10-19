import 'package:go_router/go_router.dart';

import 'features/accounts/accounts_page.dart';
import 'features/auth/auth_completion_page.dart';
import 'features/auth/login_page.dart';
import 'features/bots/bot_detail_page.dart';
import 'features/bots/create_bot_page.dart';
import 'features/bots/pull_request_page.dart';
import 'features/dashboard/dashboard_page.dart';
import 'features/notifications/notifications_page.dart';
import 'features/settings/settings_page.dart';
import 'features/shell/app_shell.dart';

GoRouter createAppRouter({String initialLocation = '/dashboard'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(path: '/auth/complete', builder: (context, state) => const AuthCompletionPage()),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/dashboard', builder: (context, state) => const DashboardPage()),
            GoRoute(path: '/bots/new', builder: (context, state) => const CreateBotPage()),
            GoRoute(
              path: '/bots/:botId/pull-requests/:pullRequestId',
              builder: (context, state) => PullRequestPage(
                botId: state.pathParameters['botId']!,
                pullRequestId: state.pathParameters['pullRequestId']!,
              ),
            ),
            GoRoute(
              path: '/bots/:botId',
              builder: (context, state) => BotDetailPage(botId: state.pathParameters['botId']!),
            ),
            GoRoute(path: '/accounts', builder: (context, state) => const AccountsPage()),
            GoRoute(path: '/notifications', builder: (context, state) => const NotificationsPage()),
            GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
          ],
        ),
      ],
      errorBuilder: (context, state) => LoginPage(error: state.error?.toString()),
    );