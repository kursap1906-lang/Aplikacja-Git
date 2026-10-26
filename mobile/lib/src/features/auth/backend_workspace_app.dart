import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../control_center_theme.dart';
import '../workspace/live_workspace_home.dart';
import 'auth_completion_page.dart';
import 'backend_setup_home.dart';
import 'authenticated_workspace_gate.dart';
import '../bots/bot_detail_page.dart';
import '../bots/pull_request_page.dart';

class BackendWorkspaceApp extends StatefulWidget {
  const BackendWorkspaceApp({required this.initialUri, super.key});

  final Uri initialUri;

  @override
  State<BackendWorkspaceApp> createState() => _BackendWorkspaceAppState();
}

class _BackendWorkspaceAppState extends State<BackendWorkspaceApp> {
  late final _router = GoRouter(
    initialLocation: Uri(
      path: widget.initialUri.path,
      query: widget.initialUri.hasQuery ? widget.initialUri.query : null,
    ).toString(),
    overridePlatformDefaultLocation: true,
    redirect: (context, state) {
      if (state.uri.path.length > 1 && state.uri.path.endsWith('/')) {
        return state.uri
            .replace(
              path: state.uri.path.substring(0, state.uri.path.length - 1),
            )
            .toString();
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/workspace'),
      GoRoute(
        path: '/connect',
        builder: (context, state) => const BackendSetupHome(),
      ),
      GoRoute(
        path: '/auth/complete',
        builder: (context, state) => AuthCompletionPage(
          callbackUri: state.uri,
          onCompleted: () async => context.replace('/connect'),
          onRetry: () async => context.replace('/connect'),
        ),
      ),
      GoRoute(
        path: '/workspace',
        builder: (context, state) => const LiveWorkspaceRoot(),
      ),
      GoRoute(path: '/dashboard', redirect: (context, state) => '/workspace'),
      GoRoute(
        path: '/bots/:botId',
        builder: (context, state) => AuthenticatedWorkspaceGate(
          builder: (context, session, logout) => Scaffold(
            appBar: AppBar(
              title: const Text('Review bota'),
              leading: IconButton(
                onPressed: () => context.go('/workspace'),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: BotDetailPage(botId: state.pathParameters['botId']!),
          ),
        ),
      ),
      GoRoute(
        path: '/bots/:botId/pull-requests/:pullRequestId',
        builder: (context, state) => AuthenticatedWorkspaceGate(
          builder: (context, session, logout) => Scaffold(
            appBar: AppBar(
              title: const Text('Pull Request i dowody testów'),
              leading: IconButton(
                onPressed: () =>
                    context.go('/bots/${state.pathParameters['botId']}'),
                icon: const Icon(Icons.arrow_back),
              ),
            ),
            body: PullRequestPage(
              botId: state.pathParameters['botId']!,
              pullRequestId: state.pathParameters['pullRequestId']!,
            ),
          ),
        ),
      ),
      GoRoute(path: '/login', redirect: (context, state) => '/connect'),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Nie znaleziono strony panelu.'),
            TextButton(
              onPressed: () => context.go('/workspace'),
              child: const Text('Otwórz panel'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Copilot Control Center',
    debugShowCheckedModeBanner: false,
    theme: controlCenterTheme(),
    routerConfig: _router,
  );
}
